# Senzing Entity Resolution Infrastructure - Azure Bicep (Entra ID Password Auth)

Azure Bicep templates for deploying Senzing entity resolution infrastructure using **Entra ID Password Authentication** (no Managed Identity).

## Table of Contents

- [Complete Deployment Sequence](#complete-deployment-sequence)
- [Performance](#performance)
- [Key Differences from MI Version](#key-differences-from-mi-version)
- [Pre-requisites (IMPORTANT!)](#pre-requisites-important)
- [Monitoring Cheat Sheet](#monitoring-cheat-sheet)
- [Architecture Overview](#architecture-overview)
- [Validation](#validation)
- [Step-by-Step Guide](#step-by-step-guide)
- [Connecting to Tools Container](#connecting-to-tools-container)
- [Managing Jobs](#managing-jobs)
- [Database Access](#database-access)
- [Cleanup](#cleanup)
- [Reference](#reference)
- [Troubleshooting](#troubleshooting)

---

## Complete Deployment Sequence

Copy-paste these commands in order for a complete deployment from scratch.

### 1. Create ACR Token (one-time ever, reuse across deployments)

Skip this step if you already have a token. The token persists in ACR and works for all deployments.

```bash
# Create scope map (fails if exists - that's OK)
az acr scope-map create \
  --name senzing-pull-scope \
  --registry RonACRPerfTesting \
  --repository senzingsdk-tools-mssql content/read \
  --repository sz_sb_consumer content/read \
  --repository redoer content/read \
  --repository stream-producer content/read

# Create token (fails if exists - that's OK)
az acr token create \
  --name senzing-pull-token \
  --registry RonACRPerfTesting \
  --scope-map senzing-pull-scope
```

**Generate password** (only run this once - it invalidates previous passwords!):
```bash
az acr token credential generate \
  --name senzing-pull-token \
  --registry RonACRPerfTesting \
  --password1
# Copy the "value" field - that's your ACR_TOKEN_PASSWORD
# WARNING: Running this again generates a NEW password and invalidates the old one!
```

### 2. Set Environment Variables

```bash
# Required - set these values
export RESOURCE_GROUP="senzing-perf-rg"
export LOCATION="eastus2"
export SENZING_LICENSE=$(base64 -w 0 /path/to/senzing-license.json)
export ENTRA_USER="senzing-svc@yourdomain.com"
export ENTRA_PASSWORD="your-password"
export ACR_TOKEN_NAME="senzing-pull-token"
export ACR_TOKEN_PASSWORD="paste-password-from-step-1"

# Derived - run these
export ENTRA_OBJECT_ID=$(az ad user show --id "$ENTRA_USER" --query id -o tsv)
echo "Entra Object ID: $ENTRA_OBJECT_ID"
```

> **Note:** The Entra user must exist and NOT have MFA enabled. See [Pre-requisites](#pre-requisites-important) if you need to create one.

### 3. Create Resource Group

```bash
az group create --name $RESOURCE_GROUP --location $LOCATION
```

### 4. Deploy Infrastructure (without StreamLoader)

```bash
az deployment group create \
  --name senzing-deployment \
  --resource-group $RESOURCE_GROUP \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters senzingLicenseBase64=$SENZING_LICENSE \
  --parameters entraUserEmail=$ENTRA_USER \
  --parameters entraUserObjectId=$ENTRA_OBJECT_ID \
  --parameters entraUserPassword=$ENTRA_PASSWORD \
  --parameters acrUsername=$ACR_TOKEN_NAME \
  --parameters acrPassword=$ACR_TOKEN_PASSWORD \
  --parameters runStreamProducer=true \
  --parameters skipStreamLoader=true \
  --parameters recordMax=2000000
```

### 5. Set Resource Prefix

```bash
export RESOURCE_PREFIX=$(az deployment group show \
  --name senzing-deployment \
  --resource-group $RESOURCE_GROUP \
  --query 'properties.outputs.sqlServerFqdn.value' -o tsv | cut -d'.' -f1 | sed 's/-sql$//')
export SB_NAMESPACE="${RESOURCE_PREFIX}-bus"
export SQL_SERVER="${RESOURCE_PREFIX}-sql"
echo "Resource Prefix: $RESOURCE_PREFIX"
```

### 6. Run Init Jobs (in order, wait for each)

```bash
# 6a. Initialize database schema
az containerapp job start --name "${RESOURCE_PREFIX}-init-db" --resource-group $RESOURCE_GROUP
watch -n 5 "az containerapp job execution list --name ${RESOURCE_PREFIX}-init-db --resource-group $RESOURCE_GROUP --query '[0].properties.status' -o tsv"
# Wait for: Succeeded

# 6b. Configure database performance settings
az containerapp job start --name "${RESOURCE_PREFIX}-config-db" --resource-group $RESOURCE_GROUP
watch -n 5 "az containerapp job execution list --name ${RESOURCE_PREFIX}-config-db --resource-group $RESOURCE_GROUP --query '[0].properties.status' -o tsv"
# Wait for: Succeeded

# 6c. Create Entra ID database user
az containerapp job start --name "${RESOURCE_PREFIX}-entra" --resource-group $RESOURCE_GROUP
watch -n 5 "az containerapp job execution list --name ${RESOURCE_PREFIX}-entra --resource-group $RESOURCE_GROUP --query '[0].properties.status' -o tsv"
# Wait for: Succeeded

# 6d. Configure Senzing data sources
az containerapp job start --name "${RESOURCE_PREFIX}-g2config" --resource-group $RESOURCE_GROUP
watch -n 5 "az containerapp job execution list --name ${RESOURCE_PREFIX}-g2config --resource-group $RESOURCE_GROUP --query '[0].properties.status' -o tsv"
# Wait for: Succeeded
```

### 7. Start Producers (fill the queue)

```bash
export PRODUCER_JOBS=$(az deployment group show \
  --name senzing-deployment \
  --resource-group $RESOURCE_GROUP \
  --query 'properties.outputs.streamProducerJobNames.value[]' -o tsv)

echo "$PRODUCER_JOBS" | while read job; do
  echo "Starting $job..."
  az containerapp job start --name "$job" --resource-group $RESOURCE_GROUP &
done
wait
echo "All producers started"
```

### 8. Wait for Queue to Fill

```bash
# Check producer status
echo "$PRODUCER_JOBS" | while read job; do
  STATUS=$(az containerapp job execution list --name "$job" --resource-group $RESOURCE_GROUP --query '[0].properties.status' -o tsv 2>/dev/null)
  echo "$job: $STATUS"
done

# Watch queue depth (wait until it reaches target, e.g., 2000000)
watch -n 10 "az servicebus queue show --namespace-name $SB_NAMESPACE --resource-group $RESOURCE_GROUP --name senzing-input --query 'messageCount' -o tsv"
```

### 9. Deploy StreamLoader (start the perf test)

```bash
az deployment group create \
  --name senzing-deployment \
  --resource-group $RESOURCE_GROUP \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters senzingLicenseBase64=$SENZING_LICENSE \
  --parameters entraUserEmail=$ENTRA_USER \
  --parameters entraUserObjectId=$ENTRA_OBJECT_ID \
  --parameters entraUserPassword=$ENTRA_PASSWORD \
  --parameters acrUsername=$ACR_TOKEN_NAME \
  --parameters acrPassword=$ACR_TOKEN_PASSWORD \
  --parameters runStreamProducer=false \
  --parameters skipStreamLoader=false \
  --parameters recordMax=2000000
```

### 10. Monitor Progress

```bash
# Quick status
echo "Queue: $(az servicebus queue show --namespace-name $SB_NAMESPACE --resource-group $RESOURCE_GROUP --name senzing-input --query 'messageCount' -o tsv)"
echo "Loaders: $(az containerapp replica list --name ${RESOURCE_PREFIX}-loader --resource-group $RESOURCE_GROUP --query 'length(@)')"
echo "DB CPU: $(az monitor metrics list --resource "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Sql/servers/$SQL_SERVER/databases/SZ" --metric cpu_percent --interval PT1M --query 'value[0].timeseries[0].data[-1].average' -o tsv)%"

# Watch queue drain
watch -n 30 "az servicebus queue show --namespace-name $SB_NAMESPACE --resource-group $RESOURCE_GROUP --name senzing-input --query 'messageCount' -o tsv"
```

### 11. Get Final ERPM (from Tools container)

```bash
az containerapp exec --name "${RESOURCE_PREFIX}-tools" --resource-group $RESOURCE_GROUP --command /bin/bash

# Inside container:
export ENTRA_USER=$(echo $SENZING_ENGINE_CONFIGURATION_JSON | python3 -c "import sys,json,re,urllib.parse; c=json.load(sys.stdin); m=re.search(r'mssql://([^:]+):', c['SQL']['CONNECTION']); print(urllib.parse.unquote(m.group(1)))")
export ENTRA_PASSWORD=$(echo $SENZING_ENGINE_CONFIGURATION_JSON | python3 -c "import sys,json,re,urllib.parse; c=json.load(sys.stdin); m=re.search(r'mssql://[^:]+:([^@]+)@', c['SQL']['CONNECTION']); print(urllib.parse.unquote(m.group(1)))")
export SQL_SERVER=$(echo $SENZING_ENGINE_CONFIGURATION_JSON | python3 -c "import sys,json,re; c=json.load(sys.stdin); m=re.search(r'@([^:]+):', c['SQL']['CONNECTION']); print(m.group(1))")
```

### Collect Stats

```bash
# Record counts
sqlcmd -S "$SQL_SERVER" -d SZ -U "$ENTRA_USER" -P "$ENTRA_PASSWORD" --authentication-method ActiveDirectoryPassword -Q "SELECT GETDATE(), COUNT(*) FROM DSRC_RECORD;"
sqlcmd -S "$SQL_SERVER" -d SZ -U "$ENTRA_USER" -P "$ENTRA_PASSWORD" --authentication-method ActiveDirectoryPassword -Q "SELECT GETDATE(), COUNT(*) FROM OBS_ENT;"
sqlcmd -S "$SQL_SERVER" -d SZ -U "$ENTRA_USER" -P "$ENTRA_PASSWORD" --authentication-method ActiveDirectoryPassword -Q "SELECT GETDATE(), COUNT(*) FROM RES_ENT;"
sqlcmd -S "$SQL_SERVER" -d SZ -U "$ENTRA_USER" -P "$ENTRA_PASSWORD" --authentication-method ActiveDirectoryPassword -Q "SELECT GETDATE(), COUNT(*) FROM RES_ENT_OKEY;"
sqlcmd -S "$SQL_SERVER" -d SZ -U "$ENTRA_USER" -P "$ENTRA_PASSWORD" --authentication-method ActiveDirectoryPassword -Q "SELECT GETDATE(), COUNT(*) FROM SYS_EVAL_QUEUE;"
sqlcmd -S "$SQL_SERVER" -d SZ -U "$ENTRA_USER" -P "$ENTRA_PASSWORD" --authentication-method ActiveDirectoryPassword -Q "SELECT GETDATE(), COUNT(*) FROM RES_RELATE;"
```

### Performance Metrics

```bash
# Load performance (ERPM = Entity Resolutions Per Minute)
sqlcmd -S "$SQL_SERVER" -d SZ -U "$ENTRA_USER" -P "$ENTRA_PASSWORD" --authentication-method ActiveDirectoryPassword \
  -Q "SELECT min(first_seen_dt) load_start, count(*)/(DATEDIFF_BIG(SECOND, min(first_seen_dt), max(first_seen_dt))/60) erpm, count(*) total, max(first_seen_dt)-min(first_seen_dt) duration, count(*)/DATEDIFF_BIG(SECOND, min(first_seen_dt), max(first_seen_dt)) avg_erps FROM dsrc_record;"
```

### 12. Cleanup

```bash
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

---

## Performance

Entra ID Password authentication performs **on par with Managed Identity** when configured correctly:

| Auth Method | ERPM | Records/sec | Test Configuration |
|-------------|------|-------------|-------------------|
| Managed Identity | ~57,000 | ~952 | BC_Gen5_32, 20 loaders |
| Entra Password | ~57,000 | ~952 | BC_Gen5_32, 20 loaders |

Both methods achieved identical throughput on a 2M record test with Azure SQL BC_Gen5_32.

> **Note:** Ensure the `entraUserPassword` parameter is correctly passed during deployment. A misconfigured password can cause authentication retries that severely degrade performance.

---

## Key Differences from MI Version

This project uses Entra ID Password authentication instead of Managed Identity:

| Component | bicep/ (MI version) | bicep-entra-password/ |
|-----------|---------------------|----------------------|
| SQL Database Auth | ActiveDirectoryMsi | ActiveDirectoryPassword |
| ACR Image Pull | MI role assignment | Token username/password |
| Service Bus | MI roles + SAS | SAS only |
| Key Vault | Used for secrets | Not used |
| Identity Resource | User-assigned MI | None |
| Init Job | `create-mi` | `entra` |

**Connection string format:**
```
mssql://user@domain.com:password@server:1433:database/?authentication=ActiveDirectoryPassword&encrypt=yes
```

---

## Pre-requisites (IMPORTANT!)

Before deploying, you **must** complete these setup steps:

### 1. Entra ID User (NO MFA)

The Entra ID user must already exist in Azure AD and **must NOT have MFA (multi-factor authentication) enabled**. The `ActiveDirectoryPassword` authentication method does not support MFA.

> **IMPORTANT:** If the user has MFA enabled, authentication will fail with error `AADSTS50076: Due to a configuration change... you must use multi-factor authentication`. You must either:
> - Create a dedicated service account and exclude it from MFA conditional access policies
> - Use an existing account that doesn't have MFA enforced

**Create a dedicated service account (recommended):**
```bash
# Create service account
az ad user create \
  --display-name "Senzing Service Account" \
  --user-principal-name "senzing-svc@yourdomain.com" \
  --password "YourSecurePassword123!" \
  --force-change-password-next-sign-in false

# Get the Object ID
az ad user show --id "senzing-svc@yourdomain.com" --query id -o tsv
```

Then exclude the user from MFA in Azure Portal:
1. Azure AD → Security → Conditional Access
2. Edit your MFA policy → Users → Exclude → Add the service account

**Verify user exists and get Object ID:**
```bash
az ad user show --id "senzing-svc@yourdomain.com" --query "{email:mail, objectId:id}" -o table

# Get just the Object ID (you'll need this for deployment)
export ENTRA_OBJECT_ID=$(az ad user show --id "senzing-svc@yourdomain.com" --query id -o tsv)
echo "Object ID: $ENTRA_OBJECT_ID"
```

**Save the Object ID** - you'll need it for deployment. The Object ID is a GUID like `55b967f3-ad6d-448e-b41d-4e75f860a34c`.

### 2. ACR Repository Token

Create a repository-scoped token for pulling container images:

```bash
# Create scope map for all Senzing images
az acr scope-map create \
  --name senzing-pull-scope \
  --registry RonACRPerfTesting \
  --repository senzingsdk-tools-mssql content/read \
  --repository sz_sb_consumer content/read \
  --repository redoer content/read \
  --repository stream-producer content/read

# Create token with that scope
az acr token create \
  --name senzing-pull-token \
  --registry RonACRPerfTesting \
  --scope-map senzing-pull-scope

# Generate password for token (save this output!)
az acr token credential generate \
  --name senzing-pull-token \
  --registry RonACRPerfTesting \
  --password1
```

**Save the token username and password** - you'll need them for deployment.

```json
{
  "passwords": [
    {
      "creationTime": "2025-12-09T21:49:06.686149+00:00",
      "expiry": null,
      "name": "password1",
      "value": "XXXYYYZZZ..." <---- this is the password
    },
    {
      "creationTime": "2025-12-09T19:59:29.250691+00:00",
      "expiry": null,
      "name": "password2",
      "value": null
    }
  ],
  "username": "senzing-pull-token" <---- this is the username
}
```

### 3. Azure CLI and Bicep

```bash
# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
az login

# Verify Bicep
az bicep version
```

### 4. Senzing License

Base64-encode your Senzing license:
```bash
export SENZING_LICENSE=$(base64 -w 0 /path/to/senzing-license.json)
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

# Redoer logs
az containerapp logs show \
  --name "${RESOURCE_PREFIX}-redoer" \
  --resource-group $RESOURCE_GROUP \
  --follow
```

### Record Count (from Tools container)

```bash
az containerapp exec \
  --name "${RESOURCE_PREFIX}-tools" \
  --resource-group $RESOURCE_GROUP \
  --command /bin/bash

# Inside container - see Database Access section for queries
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
│  ┌──────────────────┐  ┌──────────────────┐                                 │
│  │  Azure SQL       │  │  Service Bus     │  No Key Vault                   │
│  │  Database        │  │  (Queues)        │  No Managed Identity            │
│  │  (Entra Password)│  │  (SAS Auth)      │                                 │
│  └──────────────────┘  └──────────────────┘                                 │
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
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    Log Analytics Workspace                            │   │
│  │                    (Container Logs)                                   │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
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

---

## Validation

Before deploying, validate your Bicep templates:

### Lint/Build Check

```bash
# Validate syntax and check for issues (warnings are OK)
az bicep build --file main.bicep
```

### Dry Run (What-If)

```bash
az deployment group what-if \
  --resource-group $RESOURCE_GROUP \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters senzingLicenseBase64=$SENZING_LICENSE \
  --parameters entraUserEmail=$ENTRA_USER \
  --parameters entraUserObjectId=$ENTRA_OBJECT_ID \
  --parameters entraUserPassword=$ENTRA_PASSWORD \
  --parameters acrUsername=$ACR_TOKEN_NAME \
  --parameters acrPassword=$ACR_TOKEN_PASSWORD \
  --parameters runStreamProducer=true \
  --parameters recordMax=25000000
```

---

## Step-by-Step Guide

### Step 1: Set Environment Variables

```bash
export RESOURCE_GROUP="senzing-perf-rg"
export LOCATION="eastus2"

# Senzing license
export SENZING_LICENSE=$(base64 -w 0 /path/to/senzing-license.json)

# Entra ID credentials
export ENTRA_USER="senzing@yourdomain.com"
export ENTRA_OBJECT_ID=$(az ad user show --id "$ENTRA_USER" --query id -o tsv)
export ENTRA_PASSWORD="your-entra-password" # set in main.bicepparam

# ACR token credentials (from pre-requisites)
export ACR_TOKEN_NAME="senzing-pull-token"
export ACR_TOKEN_PASSWORD="your-acr-token-password"

# Verify
echo "Resource Group: $RESOURCE_GROUP"
echo "Entra User: $ENTRA_USER"
echo "Entra Object ID: $ENTRA_OBJECT_ID"
echo "ACR Token: $ACR_TOKEN_NAME"
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

Deploy without StreamLoader (so we can fill the queue first):

```bash
az deployment group create \
  --name senzing-deployment \
  --resource-group $RESOURCE_GROUP \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters senzingLicenseBase64=$SENZING_LICENSE \
  --parameters entraUserEmail=$ENTRA_USER \
  --parameters entraUserObjectId=$ENTRA_OBJECT_ID \
  --parameters entraUserPassword=$ENTRA_PASSWORD \
  --parameters acrUsername=$ACR_TOKEN_NAME \
  --parameters acrPassword=$ACR_TOKEN_PASSWORD \
  --parameters runStreamProducer=true \
  --parameters skipStreamLoader=true \
  --parameters recordMax=2000000

```

This takes ~10-15 minutes.

**Validate:**
```bash
# Check deployment status
az deployment group show \
  --name senzing-deployment \
  --resource-group $RESOURCE_GROUP \
  --query "properties.provisioningState" -o tsv
# Expected: Succeeded

# Set resource prefix
export RESOURCE_PREFIX=$(az deployment group show \
  --name senzing-deployment \
  --resource-group $RESOURCE_GROUP \
  --query 'properties.outputs.sqlServerFqdn.value' -o tsv | cut -d'.' -f1 | sed 's/-sql$//')

echo "Resource prefix: $RESOURCE_PREFIX"
```

### Step 4: Run Initialization Jobs

Run these jobs **in order**, waiting for each to complete.

#### 4a. Initialize Database

```bash
az containerapp job start \
  --name "${RESOURCE_PREFIX}-init-db" \
  --resource-group $RESOURCE_GROUP
```

**Validate:**
```bash
watch -n 5 "az containerapp job execution list \
  --name ${RESOURCE_PREFIX}-init-db \
  --resource-group $RESOURCE_GROUP \
  --query '[0].properties.status' -o tsv"
# Wait for: Succeeded
```

#### 4b. Configure Database Performance

Sets DELAYED_DURABILITY, AUTO_CREATE_STATISTICS, and AUTO_UPDATE_STATISTICS_ASYNC:

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
# Wait for: Succeeded
```

#### 4c. Create Entra ID User

This creates the Entra ID user in the database:

```bash
az containerapp job start \
  --name "${RESOURCE_PREFIX}-entra" \
  --resource-group $RESOURCE_GROUP
```

**Validate:**
```bash
watch -n 5 "az containerapp job execution list \
  --name ${RESOURCE_PREFIX}-entra \
  --resource-group $RESOURCE_GROUP \
  --query '[0].properties.status' -o tsv"
# Wait for: Succeeded
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
# Wait for: Succeeded
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

Start all producer jobs to fill the Service Bus queue:

```bash
# Get producer job names
export PRODUCER_JOBS=$(az deployment group show \
  --name senzing-deployment \
  --resource-group $RESOURCE_GROUP \
  --query 'properties.outputs.streamProducerJobNames.value[]' -o tsv)
echo $PRODUCER_JOBS

# Start all producers
echo "$PRODUCER_JOBS" | while read job; do
  echo "Starting $job..."
  az containerapp job start --name "$job" --resource-group $RESOURCE_GROUP &
done
wait
echo "All producer jobs started"
```

**Monitor progress:**
```bash
# Check producer job statuses
echo "$PRODUCER_JOBS" | while read job; do
  STATUS=$(az containerapp job execution list --name "$job" --resource-group $RESOURCE_GROUP --query '[0].properties.status' -o tsv 2>/dev/null)
  echo "$job: $STATUS"
done

# Check queue depth
export SB_NAMESPACE="${RESOURCE_PREFIX}-bus"
watch -n 10 "az servicebus queue show \
  --namespace-name $SB_NAMESPACE \
  --resource-group $RESOURCE_GROUP \
  --name senzing-input \
  --query 'messageCount' -o tsv"
```

Wait until queue has expected record count (25M).

### Step 6: Start StreamLoader

```bash
az deployment group create \
  --name senzing-deployment \
  --resource-group $RESOURCE_GROUP \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters senzingLicenseBase64=$SENZING_LICENSE \
  --parameters entraUserEmail=$ENTRA_USER \
  --parameters entraUserObjectId=$ENTRA_OBJECT_ID \
  --parameters entraUserPassword=$ENTRA_PASSWORD \
  --parameters acrUsername=$ACR_TOKEN_NAME \
  --parameters acrPassword=$ACR_TOKEN_PASSWORD \
  --parameters runStreamProducer=false \
  --parameters skipStreamLoader=false \
  --parameters recordMax=2000000
```

**Validate:**
```bash
az containerapp replica list \
  --name "${RESOURCE_PREFIX}-loader" \
  --resource-group $RESOURCE_GROUP \
  --output table
```

### Step 7: Monitor Progress

See [Monitoring Cheat Sheet](#monitoring-cheat-sheet) for all monitoring commands.

**Quick status check:**
```bash
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
- `sqlcmd` - Direct database access

---

## Managing Jobs

### Restart Producer Jobs

Producer jobs are manual-trigger Container Apps Jobs. To restart them:

```bash
# Start a single producer job
az containerapp job start --name "${RESOURCE_PREFIX}-prod-0" --resource-group $RESOURCE_GROUP

# Start all producer jobs
echo "$PRODUCER_JOBS" | while read job; do
  echo "Starting $job..."
  az containerapp job start --name "$job" --resource-group $RESOURCE_GROUP &
done
wait
echo "All producer jobs started"
```

### Check Job Status

```bash
# List executions for a specific job
az containerapp job execution list \
  --name "${RESOURCE_PREFIX}-prod-0" \
  --resource-group $RESOURCE_GROUP \
  --output table

# Check all producer job statuses
echo "$PRODUCER_JOBS" | while read job; do
  STATUS=$(az containerapp job execution list --name "$job" --resource-group $RESOURCE_GROUP --query '[0].properties.status' -o tsv 2>/dev/null)
  echo "$job: $STATUS"
done
```

### View Job Logs

```bash
# Producer job logs (need container name)
az containerapp job logs show \
  --name "${RESOURCE_PREFIX}-prod-0" \
  --resource-group $RESOURCE_GROUP \
  --container stream-producer

# Init job logs
az containerapp job logs show \
  --name "${RESOURCE_PREFIX}-init-db" \
  --resource-group $RESOURCE_GROUP \
  --container init-database

# Configure database job logs
az containerapp job logs show \
  --name "${RESOURCE_PREFIX}-config-db" \
  --resource-group $RESOURCE_GROUP \
  --container configure-database

# Entra user creation job logs
az containerapp job logs show \
  --name "${RESOURCE_PREFIX}-entra" \
  --resource-group $RESOURCE_GROUP \
  --container create-entra-user

# G2Config job logs
az containerapp job logs show \
  --name "${RESOURCE_PREFIX}-g2config" \
  --resource-group $RESOURCE_GROUP \
  --container g2configtool
```

### Restart Init Jobs

If you need to re-run initialization (e.g., after changing credentials):

```bash
# Run in order, waiting for each to complete
az containerapp job start --name "${RESOURCE_PREFIX}-init-db" --resource-group $RESOURCE_GROUP
# Wait for Succeeded...

az containerapp job start --name "${RESOURCE_PREFIX}-config-db" --resource-group $RESOURCE_GROUP
# Wait for Succeeded...

az containerapp job start --name "${RESOURCE_PREFIX}-entra" --resource-group $RESOURCE_GROUP
# Wait for Succeeded...

az containerapp job start --name "${RESOURCE_PREFIX}-g2config" --resource-group $RESOURCE_GROUP
# Wait for Succeeded...
```

---

## Database Access

From inside the Tools container, you can query the database directly using `sqlcmd`.

### Set Up Connection Variables

```bash
# Extract credentials from SENZING_ENGINE_CONFIGURATION_JSON
export ENTRA_USER=$(echo $SENZING_ENGINE_CONFIGURATION_JSON | python3 -c "import sys,json,re,urllib.parse; c=json.load(sys.stdin); m=re.search(r'mssql://([^:]+):', c['SQL']['CONNECTION']); print(urllib.parse.unquote(m.group(1)))")
export ENTRA_PASSWORD=$(echo $SENZING_ENGINE_CONFIGURATION_JSON | python3 -c "import sys,json,re,urllib.parse; c=json.load(sys.stdin); m=re.search(r'mssql://[^:]+:([^@]+)@', c['SQL']['CONNECTION']); print(urllib.parse.unquote(m.group(1)))")
export SQL_SERVER=$(echo $SENZING_ENGINE_CONFIGURATION_JSON | python3 -c "import sys,json,re; c=json.load(sys.stdin); m=re.search(r'@([^:]+):', c['SQL']['CONNECTION']); print(m.group(1))")

echo "Entra User: $ENTRA_USER"
echo "SQL Server: $SQL_SERVER"
```

### Using sqlcmd

```bash
# Interactive SQL session
sqlcmd -S "$SQL_SERVER" -d SZ -U "$ENTRA_USER" -P "$ENTRA_PASSWORD" \
  --authentication-method ActiveDirectoryPassword

# Single query
sqlcmd -S "$SQL_SERVER" -d SZ -U "$ENTRA_USER" -P "$ENTRA_PASSWORD" \
  --authentication-method ActiveDirectoryPassword \
  -Q "SELECT COUNT(*) FROM DSRC_RECORD"
```

### Collect Stats

```bash
# Record counts
sqlcmd -S "$SQL_SERVER" -d SZ -U "$ENTRA_USER" -P "$ENTRA_PASSWORD" --authentication-method ActiveDirectoryPassword -Q "SELECT GETDATE(), COUNT(*) FROM DSRC_RECORD;"
sqlcmd -S "$SQL_SERVER" -d SZ -U "$ENTRA_USER" -P "$ENTRA_PASSWORD" --authentication-method ActiveDirectoryPassword -Q "SELECT GETDATE(), COUNT(*) FROM OBS_ENT;"
sqlcmd -S "$SQL_SERVER" -d SZ -U "$ENTRA_USER" -P "$ENTRA_PASSWORD" --authentication-method ActiveDirectoryPassword -Q "SELECT GETDATE(), COUNT(*) FROM RES_ENT;"
sqlcmd -S "$SQL_SERVER" -d SZ -U "$ENTRA_USER" -P "$ENTRA_PASSWORD" --authentication-method ActiveDirectoryPassword -Q "SELECT GETDATE(), COUNT(*) FROM RES_ENT_OKEY;"
sqlcmd -S "$SQL_SERVER" -d SZ -U "$ENTRA_USER" -P "$ENTRA_PASSWORD" --authentication-method ActiveDirectoryPassword -Q "SELECT GETDATE(), COUNT(*) FROM SYS_EVAL_QUEUE;"
sqlcmd -S "$SQL_SERVER" -d SZ -U "$ENTRA_USER" -P "$ENTRA_PASSWORD" --authentication-method ActiveDirectoryPassword -Q "SELECT GETDATE(), COUNT(*) FROM RES_RELATE;"
```

### Performance Metrics

```bash
# Load performance (ERPM = Entity Resolutions Per Minute)
sqlcmd -S "$SQL_SERVER" -d SZ -U "$ENTRA_USER" -P "$ENTRA_PASSWORD" --authentication-method ActiveDirectoryPassword \
  -Q "SELECT min(first_seen_dt) load_start, count(*)/(DATEDIFF_BIG(SECOND, min(first_seen_dt), max(first_seen_dt))/60) erpm, count(*) total, max(first_seen_dt)-min(first_seen_dt) duration, count(*)/DATEDIFF_BIG(SECOND, min(first_seen_dt), max(first_seen_dt)) avg_erps FROM dsrc_record;"
```

### Using Senzing SDK (Alternative)

```bash
# Verify config
python3 -c "
import senzing_core, os
factory = senzing_core.SzAbstractFactoryCore('test', os.environ['SENZING_ENGINE_CONFIGURATION_JSON'])
config_mgr = factory.create_configmanager()
print(f'Config ID: {config_mgr.get_default_config_id()}')
"

# Get engine stats
python3 << 'EOF'
import senzing_core
import os

factory = senzing_core.SzAbstractFactoryCore('stats', os.environ['SENZING_ENGINE_CONFIGURATION_JSON'])
engine = factory.create_engine()
stats = engine.get_stats()
print(stats)
EOF
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
| `entraUserEmail` | Entra ID user email for SQL auth (required) | - |
| `entraUserObjectId` | Entra ID user Object ID for AAD admin (required) | - |
| `entraUserPassword` | Entra ID user password (required) | - |
| `acrUsername` | ACR token name | - |
| `acrPassword` | ACR token password | - |
| `templateVariant` | `simple` or `full` | `full` |
| `baseName` | Prefix for resource names | `senzing` |
| `sqlSku` | Azure SQL SKU | `GP_Gen5_8` |
| `serviceBusSku` | `Standard` or `Premium` | `Premium` |
| `streamLoaderMaxReplicas` | Max StreamLoader instances | `35` |
| `redoerMaxReplicas` | Max Redoer instances | `5` |
| `runStreamProducer` | Create producer jobs | `false` |
| `skipStreamLoader` | Skip StreamLoader deployment | `false` |
| `recordMax` | Number of test records | `25000000` |

### Database Sizing

| AWS RDS Instance | vCPUs | Azure SQL Equivalent |
|------------------|-------|---------------------|
| db.r6i.2xlarge | 8 | GP_Gen5_8 |
| db.r6i.8xlarge | 32 | GP_Gen5_32 or BC_Gen5_32 |
| db.r6i.24xlarge | 96 | BC_Gen5_80 (Azure max) |

### File Structure

```
bicep-entra-password/
├── main.bicep                              # Main orchestration template
├── main.bicepparam                         # Default parameters
├── CLAUDE.md                               # Claude Code instructions
├── README.md                               # This file
└── modules/
    ├── containers/
    │   ├── container-apps-env.bicep        # Container Apps Environment
    │   ├── configure-database-job.bicep    # Sets DB performance options
    │   ├── create-entra-user-job.bicep     # Creates Entra ID database user
    │   ├── g2configtool-job.bicep          # Configures Senzing data sources
    │   ├── init-database-job.bicep         # Initializes Senzing database
    │   ├── redoer-app.bicep                # Redo processor
    │   ├── stream-producer-jobs.bicep      # Parallel test data loaders
    │   ├── streamloader-app.bicep          # Record loader (KEDA scaling)
    │   └── tools-app.bicep                 # Debug access container
    ├── database/
    │   └── sql-database.bicep              # Azure SQL Server + Database
    ├── messaging/
    │   └── servicebus.bicep                # Service Bus namespace + queues
    ├── monitoring/
    │   └── log-analytics.bicep             # Log Analytics workspace
    └── network/
        ├── nsg.bicep                       # Network Security Groups
        └── vnet.bicep                      # VNet + subnets + Private DNS
```

---

## Troubleshooting

### CREATE USER ... FROM EXTERNAL PROVIDER Fails

If the `entra` job fails:

```bash
# Check job logs
az containerapp job logs show \
  --name "${RESOURCE_PREFIX}-entra" \
  --resource-group $RESOURCE_GROUP
```

Common issues:
- **User doesn't exist in Azure AD**: Verify with `az ad user show --id "your-email@domain.com"`
- **SQL Server not configured for Azure AD**: The SQL Server needs Azure AD authentication enabled

### ACR Image Pull Fails

```bash
# Check for pull errors in logs
az containerapp logs show \
  --name "${RESOURCE_PREFIX}-tools" \
  --resource-group $RESOURCE_GROUP
```

Common issues:
- **Token expired**: Regenerate with `az acr token credential generate`
- **Wrong repository**: Verify token has `content/read` on all required repos
- **Wrong password**: Double-check the password from token creation

### SQL Connection Fails at Runtime

If containers start but can't connect to SQL:

1. **Check the entra job succeeded**: The Entra user must exist in the database
2. **Verify credentials**: Email and password must be correct
3. **Check connection string format**: Should have `authentication=ActiveDirectoryPassword`

```bash
# Check container logs for connection errors
az containerapp logs show \
  --name "${RESOURCE_PREFIX}-loader" \
  --resource-group $RESOURCE_GROUP
```

### MFA Error (AADSTS50076)

If you see this error:
```
AADSTS50076: Due to a configuration change made by your administrator,
or because you moved to a new location, you must use multi-factor authentication
```

**Cause:** The Entra ID user has MFA enabled. `ActiveDirectoryPassword` authentication does NOT support MFA.

**Solution:**
1. Create a dedicated service account without MFA (see Pre-requisites)
2. Exclude the service account from MFA conditional access policies
3. Redeploy with the new user's credentials
4. Re-run the `entra` job to create the user in the database

### Password Not Updated After Redeployment

If you redeploy with new credentials but containers still use old values:

```bash
# Force container restart to pick up new secrets
az containerapp update \
  --name "${RESOURCE_PREFIX}-tools" \
  --resource-group $RESOURCE_GROUP \
  --set-env-vars "RESTART_TRIGGER=$(date +%s)"
```

Container Apps don't always restart when secrets change - forcing an env var update triggers a new revision.

### StreamLoader Not Scaling

**IMPORTANT**: Never use `az containerapp update` or the Azure Portal GUI to change loader settings. Always redeploy via Bicep.

```bash
# Check scaling config
az containerapp show \
  --name "${RESOURCE_PREFIX}-loader" \
  --resource-group $RESOURCE_GROUP \
  --query "properties.template.scale" -o json
```

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

### Force New Container Image

```bash
az containerapp update \
  --name "${RESOURCE_PREFIX}-tools" \
  --resource-group $RESOURCE_GROUP \
  --set-env-vars "IMAGE_REFRESH=$(date +%s)"
```
