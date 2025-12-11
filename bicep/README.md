# Senzing Entity Resolution Infrastructure - Azure Bicep

Azure Bicep templates for deploying Senzing entity resolution infrastructure for performance testing.

## Table of Contents

- [Quick Start (25M Performance Test)](#quick-start-25m-performance-test)
- [Monitoring Cheat Sheet](#monitoring-cheat-sheet)
- [Architecture Overview](#architecture-overview)
- [Step-by-Step Guide](#step-by-step-guide)
- [Connecting to Tools Container](#connecting-to-tools-container)
- [Database Access](#database-access)
- [Cleanup](#cleanup)
- [Reference](#reference)
- [Troubleshooting](#troubleshooting)

---

## Quick Start (25M Performance Test)

```bash
# 1. Set environment variables
export RESOURCE_GROUP="senzing-perf-rg"
export LOCATION="eastus2"
export SENZING_LICENSE=$(base64 -w 0 /path/to/senzing-license.json)

# 2. Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# 3. Deploy (takes ~10-15 minutes)
az deployment group create \
  --name senzing-deployment \
  --resource-group $RESOURCE_GROUP \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters senzingLicenseBase64=$SENZING_LICENSE

# 4. Get resource prefix for job names
export RESOURCE_PREFIX=$(az deployment group show \
  --name senzing-deployment \
  --resource-group $RESOURCE_GROUP \
  --query 'properties.outputs.sqlServerFqdn.value' -o tsv | cut -d'.' -f1 | sed 's/-sql$//')

# 5. Run init jobs (wait for each to complete)
az containerapp job start --name "${RESOURCE_PREFIX}-init-db" --resource-group $RESOURCE_GROUP
az containerapp job start --name "${RESOURCE_PREFIX}-config-db" --resource-group $RESOURCE_GROUP
az containerapp job start --name "${RESOURCE_PREFIX}-create-mi" --resource-group $RESOURCE_GROUP
az containerapp job start --name "${RESOURCE_PREFIX}-g2config" --resource-group $RESOURCE_GROUP

# 6. Start producers, then unpause StreamLoader
# ... see Step-by-Step Guide below for full details
```

---

## Monitoring Cheat Sheet

All the commands you need during a performance test. Run these after setting environment variables (Step 1).

### Setup (run once per session)

```bash
# Set these from your deployment
export RESOURCE_PREFIX=$(az deployment group show \
  --name senzing-deployment \
  --resource-group $RESOURCE_GROUP \
  --query 'properties.outputs.sqlServerFqdn.value' -o tsv | cut -d'.' -f1 | sed 's/-sql$//')
export SQL_SERVER="${RESOURCE_PREFIX}-sql"
export SB_NAMESPACE="${RESOURCE_PREFIX}-bus"
```

### Queue Status

```bash
# Message count (target: 25M or 100M depending on test)
az servicebus queue show \
  --namespace-name $SB_NAMESPACE \
  --resource-group $RESOURCE_GROUP \
  --name senzing-input \
  --query 'messageCount' -o tsv

# Watch queue drain
watch -n 10 "az servicebus queue show \
  --namespace-name $SB_NAMESPACE \
  --resource-group $RESOURCE_GROUP \
  --name senzing-input \
  --query 'messageCount' -o tsv"
```

### Loader Status

```bash
# Replica count
az containerapp replica list \
  --name "${RESOURCE_PREFIX}-loader" \
  --resource-group $RESOURCE_GROUP \
  --query 'length(@)'

# Configured resources
az containerapp show \
  --name "${RESOURCE_PREFIX}-loader" \
  --resource-group $RESOURCE_GROUP \
  --query "properties.template.containers[].{cpu:resources.cpu, memory:resources.memory}" \
  -o table

# CPU/Memory usage (percentage of allocated)
az monitor metrics list \
  --resource "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.App/containerApps/${RESOURCE_PREFIX}-loader" \
  --metrics "CpuPercentage" "MemoryPercentage" "Replicas" \
  --interval PT1M \
  --query "value[].{metric:name.value, current:timeseries[0].data[-1].average}" \
  -o table

# Scaling config (verify KEDA is working)
az containerapp show \
  --name "${RESOURCE_PREFIX}-loader" \
  --resource-group $RESOURCE_GROUP \
  --query "properties.template.scale" \
  -o json
```

### Database Status

```bash
# CPU percentage (target: <90%)
az monitor metrics list \
  --resource "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Sql/servers/$SQL_SERVER/databases/SZ" \
  --metric "cpu_percent" \
  --interval PT1M \
  --query "value[0].timeseries[0].data[-5:].{time:timeStamp, cpu:average}" \
  -o table

# Database SKU
az sql db show --server $SQL_SERVER --resource-group $RESOURCE_GROUP --name SZ \
  --query '{sku:sku.name, vCores:sku.capacity}' -o table
```

### Producer Status

```bash
# Get producer job names (if not already set)
export PRODUCER_JOBS=$(az deployment group show \
  --name senzing-deployment \
  --resource-group $RESOURCE_GROUP \
  --query 'properties.outputs.streamProducerJobNames.value[]' -o tsv)

# List all producer job statuses
echo "$PRODUCER_JOBS" | while read job; do
  STATUS=$(az containerapp job execution list --name "$job" --resource-group $RESOURCE_GROUP --query '[0].properties.status' -o tsv 2>/dev/null)
  echo "$job: $STATUS"
done
```

### Logs

```bash
# Loader logs (live)
az containerapp logs show \
  --name "${RESOURCE_PREFIX}-loader" \
  --resource-group $RESOURCE_GROUP \
  --follow

# Producer job logs
az containerapp job logs show \
  --name "${RESOURCE_PREFIX}-prod-0" \
  --resource-group $RESOURCE_GROUP \
  --container stream-producer
```

### Record Count (from Tools container)

```bash
az containerapp exec \
  --name "${RESOURCE_PREFIX}-tools" \
  --resource-group $RESOURCE_GROUP \
  --command /bin/bash

# Inside container:
export CLIENT_ID=$(echo $SENZING_ENGINE_CONFIGURATION_JSON | python3 -c "import sys,json,re; c=json.load(sys.stdin); m=re.search(r'mssql://([^:]+):', c['SQL']['CONNECTION']); print(m.group(1))")
export SQL_SERVER=$(echo $SENZING_ENGINE_CONFIGURATION_JSON | python3 -c "import sys,json,re; c=json.load(sys.stdin); m=re.search(r'@([^:]+):', c['SQL']['CONNECTION']); print(m.group(1))")
sqlcmd -S $SQL_SERVER -d SZ --authentication-method ActiveDirectoryManagedIdentity -U $CLIENT_ID \
  -Q "SELECT COUNT(*) AS Records FROM DSRC_RECORD"
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Azure Resource Group                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                        Virtual Network (10.0.0.0/16)                │    │
│  │  ┌───────────────────┐ ┌───────────────────┐ ┌───────────────────┐  │    │
│  │  │ Core Subnet       │ │ Loader Subnet     │ │ Producer Subnet   │  │    │
│  │  │ (10.0.8.0/23)     │ │ (10.0.10.0/23)    │ │ (10.0.12.0/23)    │  │    │
│  │  └───────────────────┘ └───────────────────┘ └───────────────────┘  │    │
│  │  ┌─────────────────────────────────────────────────────────────┐    │    │
│  │  │                    SQL Subnet (10.0.16.0/22)                 │    │    │
│  │  └─────────────────────────────────────────────────────────────┘    │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────────┐   │
│  │  Azure SQL       │  │  Service Bus     │  │  Key Vault               │   │
│  │  Database        │  │  (Queues)        │  │  (Secrets)               │   │
│  └──────────────────┘  └──────────────────┘  └──────────────────────────┘   │
│                                                                             │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │              Three Container Apps Environments                         │ │
│  │  ┌─────────────────────┐ ┌─────────────────────┐ ┌───────────────────┐ │ │
│  │  │ Core Environment    │ │ Loader Environment  │ │Producer Environment│ │ │
│  │  │ (~20 vCPU quota)    │ │ (~100 vCPU quota)   │ │(~100 vCPU quota)  │ │ │
│  │  │ ┌───────┐ ┌───────┐ │ │ ┌─────────────────┐ │ │ ┌───────────────┐ │ │ │
│  │  │ │Tools  │ │Redoer │ │ │ │  StreamLoader   │ │ │ │Producer Jobs  │ │ │ │
│  │  │ │       │ │       │ │ │ │  (2 CPU × 35)   │ │ │ │(2 CPU × 25)   │ │ │ │
│  │  │ └───────┘ └───────┘ │ │ │  KEDA Scaling   │ │ │ │Manual Trigger │ │ │ │
│  │  │ ┌─────────────────┐ │ │ └─────────────────┘ │ │ └───────────────┘ │ │ │
│  │  │ │   Init Jobs     │ │ └─────────────────────┘ └───────────────────┘ │ │
│  │  │ └─────────────────┘ │                                               │ │
│  │  └─────────────────────┘                                               │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  ┌──────────────────┐  ┌──────────────────────────────────────────────┐     │
│  │ Managed Identity │  │  Log Analytics Workspace                     │     │
│  │ (Azure AD Auth)  │  │  (Container Logs)                            │     │
│  └──────────────────┘  └──────────────────────────────────────────────┘     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Why Three Environments?

Container Apps Consumption environments have a default vCPU quota of ~100 vCPUs. By using separate environments, each workload type gets its own quota:

| Environment | Purpose | Apps | vCPU Budget |
|-------------|---------|------|-------------|
| Core | Core services | Init Jobs, Tools, Redoer | ~20 vCPU |
| Loader | Record processing | StreamLoader (2 CPU × 35 replicas) | ~70 vCPU |
| Producer | Data loading | Producer Jobs (2 CPU × 25 jobs) | ~50 vCPU |

This prevents resource contention and allows loaders to use full 2 CPU per replica for maximum throughput.

---

## Prerequisites

1. **Azure CLI** (v2.50+)
   ```bash
   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
   az login

   # ACR login for staging images
   az acr login --name RonACRPerfTesting
   ```

2. **Bicep CLI** (included with Azure CLI 2.20+)
   ```bash
   az bicep version
   ```

3. **Senzing License** - Base64-encoded license string

4. **Azure Subscription** with permissions to create resources

---

## Validation

Before deploying, validate your Bicep templates:

### Lint/Build Check

```bash
# Validate syntax and check for issues (warnings are OK)
az bicep build --file main.bicep
```

### Dry Run (What-If)

Preview what resources will be created/modified without actually deploying:

```bash
az deployment group what-if \
  --resource-group $RESOURCE_GROUP \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters senzingLicenseBase64=$SENZING_LICENSE \
  --parameters runStreamProducer=true \
  --parameters pauseStreamLoaderForDataLoad=true \
  --parameters recordMax=25000000
```

This shows:
- Resources that will be **created** (green +)
- Resources that will be **modified** (yellow ~)
- Resources that will be **deleted** (red -)
- Resources with **no change** (gray)

---

## Step-by-Step Guide

### Step 1: Set Environment Variables

```bash
export RESOURCE_GROUP="senzing-perf-rg"
export LOCATION="eastus2"

# Encode your Senzing license
export SENZING_LICENSE=$(base64 -w 0 /path/to/senzing-license.json)

# Verify
echo "Resource Group: $RESOURCE_GROUP"
echo "Location: $LOCATION"
echo "License set: $([ -n "$SENZING_LICENSE" ] && echo 'Yes' || echo 'No')"
```

### Step 2: Create Resource Group

```bash
az group create --name $RESOURCE_GROUP --location $LOCATION
```

**Validate:**
```bash
az group show --name $RESOURCE_GROUP --query "properties.provisioningState" -o tsv
# Expected: Succeeded
```

### Step 3: Deploy Infrastructure

Deploy without StreamLoader (so we can fill the queue first, then start loaders for accurate perf measurement):

```bash
az deployment group create \
  --name senzing-deployment \
  --resource-group $RESOURCE_GROUP \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters senzingLicenseBase64=$SENZING_LICENSE \
  --parameters runStreamProducer=true \
  --parameters skipStreamLoader=true \
  --parameters recordMax=25000000
```

This takes ~10-15 minutes. For 100M records, change `recordMax=100000000`.

**Validate:**
```bash
# Check deployment status
az deployment group show \
  --name senzing-deployment \
  --resource-group $RESOURCE_GROUP \
  --query "properties.provisioningState" -o tsv
# Expected: Succeeded

# Set resource prefix for subsequent commands
export RESOURCE_PREFIX=$(az deployment group show \
  --name senzing-deployment \
  --resource-group $RESOURCE_GROUP \
  --query 'properties.outputs.sqlServerFqdn.value' -o tsv | cut -d'.' -f1 | sed 's/-sql$//')

echo "Resource prefix: $RESOURCE_PREFIX"

# Verify database SKU (should be GP_Gen5_32)
export SQL_SERVER="${RESOURCE_PREFIX}-sql"
az sql db show --server $SQL_SERVER --resource-group $RESOURCE_GROUP --name SZ \
  --query '{sku:sku.name, vCores:sku.capacity}' -o table

# List all container apps
az containerapp list --resource-group $RESOURCE_GROUP --output table
```

### Step 4: Run Initialization Jobs

Run these jobs **in order**, waiting for each to complete before starting the next.

#### 4a. Initialize Database

```bash
az containerapp job start \
  --name "${RESOURCE_PREFIX}-init-db" \
  --resource-group $RESOURCE_GROUP
```

**Validate:**
```bash
# Check status (wait for "Succeeded")
watch -n 5 "az containerapp job execution list \
  --name ${RESOURCE_PREFIX}-init-db \
  --resource-group $RESOURCE_GROUP \
  --query '[0].properties.status' -o tsv"
```

#### 4b. Configure Database Performance Settings

Sets `DELAYED_DURABILITY = Forced`, `AUTO_CREATE_STATISTICS ON`, and `AUTO_UPDATE_STATISTICS_ASYNC ON` for better write performance.

```bash
az containerapp job start \
  --name "${RESOURCE_PREFIX}-config-db" \
  --resource-group $RESOURCE_GROUP
```

**Validate:**
```bash
watch -n 5 "az containerapp job execution list \
  --name ${RESOURCE_PREFIX}-config-db \
  --resource-group $RESOURCE_GROUP \
  --query '[0].properties.status' -o tsv"
```

#### 4c. Create Managed Identity User

```bash
az containerapp job start \
  --name "${RESOURCE_PREFIX}-create-mi" \
  --resource-group $RESOURCE_GROUP
```

**Validate:**
```bash
watch -n 5 "az containerapp job execution list \
  --name ${RESOURCE_PREFIX}-create-mi \
  --resource-group $RESOURCE_GROUP \
  --query '[0].properties.status' -o tsv"
```

#### 4d. Configure Senzing Data Sources

```bash
az containerapp job start \
  --name "${RESOURCE_PREFIX}-g2config" \
  --resource-group $RESOURCE_GROUP
```

**Validate:**
```bash
watch -n 5 "az containerapp job execution list \
  --name ${RESOURCE_PREFIX}-g2config \
  --resource-group $RESOURCE_GROUP \
  --query '[0].properties.status' -o tsv"
```

**Verify config was created** (from Tools container):
```bash
az containerapp exec \
  --name "${RESOURCE_PREFIX}-tools" \
  --resource-group $RESOURCE_GROUP \
  --command /bin/bash

# Inside container:
python3 -c "
import senzing_core, os
factory = senzing_core.SzAbstractFactoryCore('test', os.environ['SENZING_ENGINE_CONFIGURATION_JSON'])
config_mgr = factory.create_configmanager()
print(f'Config ID: {config_mgr.get_default_config_id()}')
"
# Expected: Config ID: <non-zero number>
```

### Step 5: Load Test Data

Multiple parallel producer jobs load test records into the Service Bus queue. With Premium Service Bus (default), more parallel jobs are used for faster queue fill.

| Records | Stride | Producer Jobs |
|---------|--------|---------------|
| 1M | 500K | 2 jobs |
| 5M | 500K | 10 jobs |
| 10M | 500K | 20 jobs |
| 25M | 1M | 25 jobs |
| 50M | 2M | 25 jobs |
| 100M | 4M | 25 jobs |

> **Note:** These job counts are optimized for Premium Service Bus. If using Standard tier, expect throttling with this many parallel producers.

#### 5a. Get Producer Job Names

```bash
export PRODUCER_JOBS=$(az deployment group show \
  --name senzing-deployment \
  --resource-group $RESOURCE_GROUP \
  --query 'properties.outputs.streamProducerJobNames.value[]' -o tsv)

echo "Producer jobs:"
echo "$PRODUCER_JOBS"
```

#### 5b. Start All Producers

```bash
echo "$PRODUCER_JOBS" | while read job; do
  echo "Starting $job..."
  az containerapp job start --name "$job" --resource-group $RESOURCE_GROUP &
done
wait
echo "All producer jobs started"
```

#### 5c. Monitor Producer Progress

```bash
# Check status of all producers
echo "$PRODUCER_JOBS" | while read job; do
  STATUS=$(az containerapp job execution list \
    --name "$job" \
    --resource-group $RESOURCE_GROUP \
    --query '[0].properties.status' -o tsv 2>/dev/null)
  echo "$job: $STATUS"
done
```

Or use watch for continuous monitoring:
```bash
watch -n 10 'PRODUCER_JOBS=$(az deployment group show \
  --name senzing-deployment \
  --resource-group $RESOURCE_GROUP \
  --query "properties.outputs.streamProducerJobNames.value[]" -o tsv)
echo "$PRODUCER_JOBS" | while read job; do
  STATUS=$(az containerapp job execution list \
    --name "$job" \
    --resource-group $RESOURCE_GROUP \
    --query "[0].properties.status" -o tsv 2>/dev/null)
  echo "$job: $STATUS"
done'
```

**If any job fails you can restart with:**
```bash
az containerapp job start \
    --name "${RESOURCE_PREFIX}-prod-0" \
    --resource-group $RESOURCE_GROUP
```

#### 5d. Check Producer Logs

```bash
# View logs for a specific producer job
az containerapp job logs show \
  --name "${RESOURCE_PREFIX}-prod-0" \
  --resource-group $RESOURCE_GROUP \
  --container stream-producer

# Stream logs in real-time (if job is running)
az containerapp job logs show \
  --name "${RESOURCE_PREFIX}-prod-0" \
  --resource-group $RESOURCE_GROUP \
  --container stream-producer \
  --follow

# Check all producer logs quickly
echo "$PRODUCER_JOBS" | while read job; do
  echo "=== $job ==="
  az containerapp job logs show --name "$job" --resource-group $RESOURCE_GROUP --container stream-producer 2>/dev/null | tail -20
done
```

#### 5e. Check Queue Depth

```bash
export SB_NAMESPACE=$(az deployment group show \
  --name senzing-deployment \
  --resource-group $RESOURCE_GROUP \
  --query 'properties.outputs.serviceBusNamespace.value' -o tsv)

az servicebus queue show \
  --namespace-name $SB_NAMESPACE \
  --resource-group $RESOURCE_GROUP \
  --name senzing-input \
  --query 'messageCount' -o tsv
```

Wait until all producers show "Succeeded" and queue has expected record count (25M or 100M).

### Step 6: Start StreamLoader

Deploy StreamLoader to begin processing (starts with 8 replicas, scales to max based on queue depth):

```bash
az deployment group create \
  --name senzing-deployment \
  --resource-group $RESOURCE_GROUP \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters senzingLicenseBase64=$SENZING_LICENSE \
  --parameters runStreamProducer=false \
  --parameters skipStreamLoader=false \
  --parameters recordMax=25000000
```

**Validate StreamLoader is running:**
```bash
az containerapp replica list \
  --name "${RESOURCE_PREFIX}-loader" \
  --resource-group $RESOURCE_GROUP \
  --output table

# Get replica count
az containerapp replica list \
  --name "${RESOURCE_PREFIX}-loader" \
  --resource-group $RESOURCE_GROUP \
  --query 'length(@)'
```

### Step 7: Monitor Progress

See [Monitoring Cheat Sheet](#monitoring-cheat-sheet) for all monitoring commands.

**Key things to watch:**
1. **Queue depth** - Should decrease as loaders process records
2. **Loader replicas** - KEDA scales based on queue depth (min 8, max per config)
3. **Database CPU** - Target <90%. If saturated, loaders wait on DB
4. **Record count** - Check progress in database via Tools container

**Quick status check:**
```bash
# Queue + Loaders + DB CPU in one view
echo "Queue: $(az servicebus queue show --namespace-name $SB_NAMESPACE --resource-group $RESOURCE_GROUP --name senzing-input --query 'messageCount' -o tsv)"
echo "Loaders: $(az containerapp replica list --name ${RESOURCE_PREFIX}-loader --resource-group $RESOURCE_GROUP --query 'length(@)')"
echo "DB CPU: $(az monitor metrics list --resource "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Sql/servers/$SQL_SERVER/databases/SZ" --metric cpu_percent --interval PT1M --query 'value[0].timeseries[0].data[-1].average' -o tsv)%"
```

---

## Connecting to Tools Container

```bash
az containerapp exec \
  --name "${RESOURCE_PREFIX}-tools" \
  --resource-group $RESOURCE_GROUP \
  --command /bin/bash
```

Available tools inside the container:
- `sz_configtool` - Configure Senzing data sources
- `sz_explorer` - Explore entities and relationships
- `sqlcmd` - Direct database access (Go version with MI support)

---

## Database Access

From inside the Tools container:

```bash
# Set up connection variables
export CLIENT_ID=$(echo $SENZING_ENGINE_CONFIGURATION_JSON | python3 -c "import sys,json,re; c=json.load(sys.stdin); m=re.search(r'mssql://([^:]+):', c['SQL']['CONNECTION']); print(m.group(1))")
export SQL_SERVER=$(echo $SENZING_ENGINE_CONFIGURATION_JSON | python3 -c "import sys,json,re; c=json.load(sys.stdin); m=re.search(r'@([^:]+):', c['SQL']['CONNECTION']); print(m.group(1))")

# Interactive SQL session
sqlcmd -S $SQL_SERVER -d SZ --authentication-method ActiveDirectoryManagedIdentity -U $CLIENT_ID

# Single query
sqlcmd -S $SQL_SERVER -d SZ --authentication-method ActiveDirectoryManagedIdentity -U $CLIENT_ID \
  -Q "SELECT COUNT(*) FROM DSRC_RECORD"
```

**Collect stats:**
```bash
sqlcmd -S $SQL_SERVER -d SZ --authentication-method ActiveDirectoryManagedIdentity -U $CLIENT_ID -Q "SELECT COUNT(*) AS Records FROM DSRC_RECORD"
sqlcmd -S $SQL_SERVER -d SZ --authentication-method ActiveDirectoryManagedIdentity -U $CLIENT_ID -Q "SELECT GETDATE(), COUNT(*) FROM DSRC_RECORD;"
sqlcmd -S $SQL_SERVER -d SZ --authentication-method ActiveDirectoryManagedIdentity -U $CLIENT_ID -Q "SELECT GETDATE(), COUNT(*) FROM OBS_ENT;"
sqlcmd -S $SQL_SERVER -d SZ --authentication-method ActiveDirectoryManagedIdentity -U $CLIENT_ID -Q "SELECT GETDATE(), COUNT(*) FROM RES_ENT;"
sqlcmd -S $SQL_SERVER -d SZ --authentication-method ActiveDirectoryManagedIdentity -U $CLIENT_ID -Q "SELECT GETDATE(), COUNT(*) FROM RES_ENT_OKEY;"
sqlcmd -S $SQL_SERVER -d SZ --authentication-method ActiveDirectoryManagedIdentity -U $CLIENT_ID -Q "SELECT GETDATE(), COUNT(*) FROM SYS_EVAL_QUEUE;"
sqlcmd -S $SQL_SERVER -d SZ --authentication-method ActiveDirectoryManagedIdentity -U $CLIENT_ID -Q "SELECT GETDATE(), COUNT(*) FROM RES_RELATE;"

sqlcmd -S $SQL_SERVER -d SZ --authentication-method ActiveDirectoryManagedIdentity -U $CLIENT_ID -Q "select min(first_seen_dt) load_start, count(*)/(DATEDIFF_BIG(SECOND, min(first_seen_dt), max(first_seen_dt))/60) erpm, count(*) total, max(first_seen_dt)-min(first_seen_dt) duration, count(*)/DATEDIFF_BIG(SECOND, min(first_seen_dt), max(first_seen_dt)) avg_erps from dsrc_record;"
```

**Useful queries:**

Use `GO` after each to execute them.

```sql
-- List tables
SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME;

-- Check Senzing config
SELECT * FROM SYS_CFG;

-- List data sources
SELECT * FROM SYS_CODES_DSRC;

-- Record count
SELECT COUNT(*) FROM DSRC_RECORD;

-- Entity count
SELECT COUNT(*) FROM RES_ENT_OKEY;

-- Redo count
SELECT COUNT(*) FROM SYS_EVAL_QUEUE;
```

---

## Cleanup

```bash
az group delete --name $RESOURCE_GROUP --yes --no-wait

# Monitor deletion
watch -n 5 "az group exists --name $RESOURCE_GROUP"
```

---

## Reference

### Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `senzingLicenseBase64` | Base64-encoded Senzing license (required) | - |
| `templateVariant` | `simple` (Tools only) or `full` (all services) | `full` |
| `baseName` | Prefix for resource names | `senzing` |
| `sqlSku` | Azure SQL SKU | `GP_Gen5_32` |
| `serviceBusSku` | Service Bus tier: `Standard` (throttled) or `Premium` (dedicated) | `Premium` |
| `streamLoaderMinReplicas` | Min StreamLoader instances (set to match AWS) | `8` |
| `streamLoaderMaxReplicas` | Max StreamLoader instances | `35` |
| `redoerMaxReplicas` | Max Redoer instances | `5` |
| `runStreamProducer` | Create producer jobs for test data | `false` |
| `skipStreamLoader` | Skip StreamLoader deployment (deploy later for perf test) | `false` |
| `recordMax` | Number of test records | `25000000` |
| `testDataInputUrl` | Test data file URL | Azure Blob URL |

### Performance Tuning

#### Data Source Location

For fastest test data loading, use Azure Blob Storage in the same region as your Container Apps:

| Data Source | Performance | Notes |
|-------------|-------------|-------|
| Azure Blob (same region) | ~15,000 records/sec | Default - fastest |
| AWS S3 (cross-cloud) | ~220 records/sec | 70x slower |

The default `testDataInputUrl` points to Azure Blob Storage. If you need to use a different source, override in deployment:

```bash
--parameters testDataInputUrl='https://your-storage.blob.core.windows.net/data/test-dataset-100m.json.gz'
```

#### Container Resource Allocation

**StreamLoader** (per replica, in Loader Environment):
- **CPU**: 2.0 cores
- **Memory**: 4Gi
- Runs in dedicated Loader environment for independent vCPU quota

**Producer Jobs** (each job, in Producer Environment):
- **CPU**: 2 cores (Container Apps max)
- **Memory**: 4Gi (Container Apps max)
- **Threads**: 30 concurrent
- **Read Buffer**: 500 records
- Runs in dedicated Producer environment for independent vCPU quota

**Core Services** (Tools, Redoer, Init Jobs):
- **CPU**: 0.5-1.0 cores
- **Memory**: 1-2Gi
- Runs in Core environment

> **Three Environment Architecture**: Each Container Apps Environment has its own ~100 vCPU quota. By separating workloads into Core, Loader, and Producer environments, each can scale independently without resource contention.

The stride dynamically adjusts based on total record count. With Premium Service Bus (default), more parallelism is used:

| Record Range | Stride | Max Jobs |
|--------------|--------|----------|
| ≤5M | 500K | 10 |
| ≤10M | 500K | 20 |
| ≤25M | 1M | 25 |
| ≤50M | 2M | 25 |
| 100M | 4M | 25 |

> **Note**: Container Apps consumption plan limits containers to max 2 CPU / 4Gi memory. With Premium Service Bus, the parallelization across 25 jobs compensates for per-container limits.

### Database Sizing

#### AWS to Azure SQL Mapping

| AWS RDS Instance | vCPUs | Memory | Azure SQL Equivalent |
|------------------|-------|--------|---------------------|
| db.r6i.2xlarge | 8 | 64 GB | GP_Gen5_8 |
| db.r6i.8xlarge | 32 | 256 GB | GP_Gen5_32 or BC_Gen5_32 |
| db.r6i.24xlarge | 96 | 768 GB | BC_Gen5_80 (Azure max) |

#### Azure SQL SKU Types

| Prefix | Tier | Storage | Cost (32 vCore) | Best For |
|--------|------|---------|-----------------|----------|
| GP_ | General Purpose | Remote | ~$1,200/month | Development, testing |
| BC_ | Business Critical | Local SSD | ~$3,200/month | Production, write-heavy |

> **Note:** Azure SQL maxes out at 80 vCores per database. For workloads exceeding this, consider Azure SQL Managed Instance or sharding.

#### Pre-configured Test Configurations

The `main.bicepparam` file includes pre-configured settings for common test scenarios. Uncomment the desired configuration:

| Configuration | SQL SKU | Max Loaders | Est. Time | Monthly Cost |
|---------------|---------|-------------|-----------|--------------|
| 25M Standard | GP_Gen5_32 | 35 | ~2-3 hrs | ~$1,200 |
| 25M Fast | BC_Gen5_32 | 40 | ~1-1.5 hrs | ~$3,200 |
| 50M | GP_Gen5_32 | 35 | ~4-5 hrs | ~$1,200 |
| 100M | BC_Gen5_80 | 50 | ~8-10 hrs | ~$8,000 |

> **Note**: With 2 CPU per loader, max loaders is ~50 per environment (~100 vCPU quota). Monitor CPU usage - if loaders are I/O bound (<50% CPU), you can reduce to 1 CPU per loader to double the replica count.

**To switch configurations**, edit `main.bicepparam`:

```bicep
// Comment out the current configuration...
// param sqlSku = 'GP_Gen5_32'
// param streamLoaderMaxReplicas = 35
// ...

// ...and uncomment the one you want:
param sqlSku = 'BC_Gen5_80'
param streamLoaderMaxReplicas = 60
param redoerMaxReplicas = 10
param runStreamProducer = false
param recordMax = 100000000
```

**Or override at deployment time:**

```bash
az deployment group create \
  --name senzing-deployment \
  --resource-group $RESOURCE_GROUP \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters senzingLicenseBase64=$SENZING_LICENSE \
  --parameters sqlSku='BC_Gen5_80' \
  --parameters streamLoaderMaxReplicas=60 \
  --parameters recordMax=100000000
```

### File Structure

```
bicep/
├── main.bicep                              # Main orchestration template
├── main.bicepparam                         # Default parameters
└── modules/
    ├── containers/
    │   ├── container-apps-env.bicep        # Container Apps Environment
    │   ├── configure-database-job.bicep    # Sets database performance options
    │   ├── create-mi-user-job.bicep        # Creates MI database user
    │   ├── g2configtool-job.bicep          # Configures Senzing data sources
    │   ├── init-database-job.bicep         # Initializes Senzing database
    │   ├── redoer-app.bicep                # Redo processor
    │   ├── stream-producer-jobs.bicep      # Parallel test data loaders
    │   ├── streamloader-app.bicep          # Record loader (KEDA scaling)
    │   └── tools-app.bicep                 # Debug access container
    ├── database/
    │   ├── managed-identity.bicep          # User-assigned Managed Identity
    │   └── sql-database.bicep              # Azure SQL Server + Database
    ├── messaging/
    │   └── servicebus.bicep                # Service Bus namespace + queues
    ├── monitoring/
    │   └── log-analytics.bicep             # Log Analytics workspace
    ├── network/
    │   ├── nsg.bicep                       # Network Security Groups
    │   └── vnet.bicep                      # VNet + subnets + Private DNS
    └── security/
        └── keyvault.bicep                  # Key Vault for secrets
```

---

## Troubleshooting

### Job Failed

```bash
# Check job status
az containerapp job execution list \
  --name "${RESOURCE_PREFIX}-init-db" \
  --resource-group $RESOURCE_GROUP \
  --output table

# View job logs
az containerapp job logs show \
  --name "${RESOURCE_PREFIX}-init-db" \
  --resource-group $RESOURCE_GROUP
```

### StreamLoader Not Scaling

**IMPORTANT**: Never use `az containerapp update` or the Azure Portal GUI to change loader settings. This wipes KEDA scaling metadata and breaks auto-scaling. Always redeploy via Bicep instead.

```bash
# Check scaling config (verify KEDA rules exist)
az containerapp show \
  --name "${RESOURCE_PREFIX}-loader" \
  --resource-group $RESOURCE_GROUP \
  --query "properties.template.scale" -o json

# If rules array is empty or missing, KEDA was wiped. Redeploy:
az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters senzingLicenseBase64=$SENZING_LICENSE

# Check for multiple revisions (GUI creates new revisions)
az containerapp revision list \
  --name "${RESOURCE_PREFIX}-loader" \
  --resource-group $RESOURCE_GROUP \
  --query "[].{name:name, active:properties.active, replicas:properties.replicas}" \
  -o table
```

### Scaling Stuck at Wrong Count

If KEDA shows correct config (maxReplicas=20) but replicas are stuck at a lower number (e.g., 15), check for stale revisions:

```bash
az containerapp revision list \
  --name "${RESOURCE_PREFIX}-loader" \
  --resource-group $RESOURCE_GROUP \
  --query "[].{name:name, active:properties.active, replicas:properties.replicas}" \
  -o table
```

If there are multiple Active revisions (especially one with high replica count but 0 actually running), deactivate the old ones:

```bash
az containerapp revision deactivate \
  --name "${RESOURCE_PREFIX}-loader" \
  --revision "<old-revision-name>" \
  --resource-group $RESOURCE_GROUP
```

This can happen after GUI/CLI changes create orphan revisions that confuse KEDA's scaling logic. After deactivating stale revisions, scaling should resume normally.

### Exceeded Resource Quota

If revisions show "Exceeded resource quota. 0/N replicas ready", a Container Apps Environment has hit its CPU/memory limit.

**Check in Azure Portal**: Container Apps → your-app → Revisions and replicas → look for "Running status details"

**With Three Environment Architecture** (default), this should be rare:
- Loaders (2 CPU × 35 = 70 vCPU) run in dedicated Loader environment (~100 vCPU quota)
- Producers (2 CPU × 25 = 50 vCPU) run in dedicated Producer environment (~100 vCPU quota)
- Core services run in Core environment (~100 vCPU quota)

**If you still hit quota limits**:

1. **Reduce max replicas** in `main.bicepparam`:
   ```bicep
   param streamLoaderMaxReplicas = 30  // Instead of 35
   ```

2. **Request quota increase**: Azure Portal → Search "Quotas" → My quotas → filter by "Container Apps", or create a support request

**Resource calculation**: Each StreamLoader uses 2 CPUs. With 35 loaders = 70 vCPUs in the Loader environment. Each Producer job uses 2 CPUs. With 25 jobs = 50 vCPUs in the Producer environment.

### Key Vault Access Denied

If you need to access Key Vault secrets:

```bash
USER_ID=$(az ad signed-in-user show --query id -o tsv)
VAULT_NAME=$(az keyvault list --resource-group $RESOURCE_GROUP --query '[0].name' -o tsv)
KV_ID=$(az keyvault show --name $VAULT_NAME --resource-group $RESOURCE_GROUP --query id -o tsv)

az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee $USER_ID \
  --scope $KV_ID

# Wait ~30 seconds, then access secrets
az keyvault secret show --vault-name $VAULT_NAME --name sql-admin-password --query value -o tsv
```

### Database Password Authentication

If you need to connect with SQL password instead of Managed Identity:

```bash
# Get password from Key Vault (requires Key Vault access above)
SQL_PASSWORD=$(az keyvault secret show \
  --vault-name $VAULT_NAME \
  --name sql-admin-password \
  --query value -o tsv)

SQL_SERVER=$(az deployment group show \
  --name senzing-deployment \
  --resource-group $RESOURCE_GROUP \
  --query 'properties.outputs.sqlServerFqdn.value' -o tsv)

# Connect from Tools container
sqlcmd -S $SQL_SERVER -U senzing -P "$SQL_PASSWORD" -d SZ
```

### Force New Container Image

If you've pushed a new image and need the container to pull it:

```bash
az containerapp update \
  --name "${RESOURCE_PREFIX}-tools" \
  --resource-group $RESOURCE_GROUP \
  --set-env-vars "IMAGE_REFRESH=$(date +%s)"

# Deactivate old revision if needed
az containerapp revision list \
  --name "${RESOURCE_PREFIX}-tools" \
  --resource-group $RESOURCE_GROUP \
  --output table
```
