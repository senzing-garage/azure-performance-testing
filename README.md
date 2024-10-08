# azure-performance-testing

[Azure portal](http://portal.azure.com/)

# Running tests:

## set up:

### in variables

- set appropriate number of records to run
- update any other vars

### in environment (once for the shell):

- `export TF_VAR_senzing_license_string=<license_string>`

### for az env (once for the shell):

- login to Azure portal: https://portal.azure.com/#home
- `az login`

If needed: [set up Azure CLI](#Azure-CLI)

## bring up the stack:

```
terraform init -upgrade
terraform validate
terraform plan -out main.tfplan
terraform apply main.tfplan
```

- verify that the appropriate number of messages are in the queue via the [Azure portal](http://portal.azure.com/)

## to destroy the stack when all done:

```
terraform plan -destroy -out main.destroy.tfplan
terraform apply main.destroy.tfplan
```

### initialize database and bring up loaders:

#### export the env vars from the terraform:

```
terraform output -json | jq -r '@sh "export AZURE_ANIMAL=\(.AZURE_ANIMAL.value)\nexport SENZING_AZURE_QUEUE_CONNECTION_STRING=\(.SENZING_AZURE_QUEUE_CONNECTION_STRING.value)\nexport SENZING_AZURE_QUEUE_NAME=\(.SENZING_AZURE_QUEUE_NAME.value)\nexport SENZING_DB_PWD=\(.db_admin_password.value)\nexport SENZING_ENGINE_CONFIGURATION_JSON=\(.SENZING_ENGINE_CONFIGURATION_JSON.value| gsub("[ \\n\\t]"; ""))"' > env.sh

source env.sh
```

### get AKS credentials:

```
az aks get-credentials --resource-group $AZURE_ANIMAL-rg --name $AZURE_ANIMAL-cluster
```

#### initialize the database and bring up a tools container:

```
envsubst < init-tools-deployment.yaml | kubectl apply -f -
```
Use `kubectl exec --stdin --tty <tools pod id> -- /bin/bash` to run database queries from tools pod

to delete:

```
kubectl delete deployment sz-init-database
kubectl delete deployment sz-tools
kubectl delete configmap sz-script-configmap
```

### deploy loaders:

```
envsubst < loader-deployment.yaml | kubectl apply -f -
```

## Monitor progress:

### check producer logs:

- name is `$AZURE_ANIMAL-continst-0` or `$AZURE_ANIMAL-continst-1`
- container for
  - `$AZURE_ANIMAL-continst-0`
    - `$AZURE_ANIMAL-senzing-producer-0`
    - `$AZURE_ANIMAL-senzing-producer-1`
    - `$AZURE_ANIMAL-senzing-producer-2`
    - `$AZURE_ANIMAL-senzing-producer-3`
  - `$AZURE_ANIMAL-continst-1`
    - `$AZURE_ANIMAL-senzing-producer-10`
    - `$AZURE_ANIMAL-senzing-producer-11`
    - `$AZURE_ANIMAL-senzing-producer-12`
    - `$AZURE_ANIMAL-senzing-producer-13`

```
az container logs --resource-group $AZURE_ANIMAL-rg --name $AZURE_ANIMAL-continst-1 --container $AZURE_ANIMAL-senzing-producer-11
```

### check loader pods, deplyents, and logs:

```
kubectl get pods --watch
kubectl get pod <pod name>
kubectl logs <pod_name>
kubectl logs -f <pod_name>
kubectl exec --stdin --tty <pod name> -- /bin/bash
kubectl get deployment
kubectl delete deployment <deployment name>
kubectl delete configmap <configmap name>
```

### check service bus queue:

```
az servicebus queue show --resource-group $AZURE_ANIMAL-rg \
    --namespace-name $AZURE_ANIMAL-service-bus \
    --name $AZURE_ANIMAL-queue \
    --query countDetails
```

## Gather stats:

### exec into tools:

```
kubectl exec --stdin --tty <tools pod id> -- /bin/bash

#OLD: az containerapp exec --name $AZURE_ANIMAL-init-db-ca --resource-group $AZURE_ANIMAL-rg --command bash --container $AZURE_ANIMAL-senzingapi-tools
```

### inside of the tools container:

```
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "SELECT GETDATE(), COUNT(*) FROM DSRC_RECORD;"
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "SELECT GETDATE(), COUNT(*) FROM OBS_ENT;"
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "SELECT GETDATE(), COUNT(*) FROM RES_ENT;"
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "SELECT GETDATE(), COUNT(*) FROM RES_ENT_OKEY;"
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "SELECT GETDATE(), COUNT(*) FROM SYS_EVAL_QUEUE;"
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "SELECT GETDATE(), COUNT(*) FROM RES_RELATE;"

# query that is close to what the AWS query gives us
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "select min(first_seen_dt) load_start, count(*)/(DATEDIFF_BIG(SECOND, min(first_seen_dt), max(first_seen_dt))/60) erpm, count(*) total, max(first_seen_dt)-min(first_seen_dt) duration, count(*)/DATEDIFF_BIG(SECOND, min(first_seen_dt), max(first_seen_dt)) avg_erps from dsrc_record;"

# extra queries that brian wants run
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "select dr.RECORD_ID,oe.OBS_ENT_ID,reo.RES_ENT_ID from DSRC_RECORD dr left outer join OBS_ENT oe ON dr.dsrc_id = oe.dsrc_id and dr.ent_src_key = oe.ent_src_key left outer join RES_ENT_OKEY reo ON oe.OBS_ENT_ID = reo.OBS_ENT_ID where reo.RES_ENT_ID is null;"
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "select dr.RECORD_ID,reo.OBS_ENT_ID,reo.RES_ENT_ID from RES_ENT_OKEY reo left outer join OBS_ENT oe ON oe.OBS_ENT_ID = reo.OBS_ENT_ID  left outer join DSRC_RECORD dr  ON dr.dsrc_id = oe.dsrc_id and dr.ent_src_key = oe.ent_src_key where dr.RECORD_ID is null;"
```

##### get Azure SQL version

```
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "select @@version as version;"

##### attempt to repro issue:
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "DBCC FREEPROCCACHE WITH NO_INFOMSGS;"

sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE"
g2cmd:  searchByAttributes '{"NAME_FIRST": "RRUTH","NAME_LAST": "HAVEN","ADDR_CITY": "Holtwood","ADDR_LINE1": "206 BethesdaChurch ROAD","ADDR_POSTAL_CODE": "17532"}'
```


### Charts and graphs

- TODO

#### search logs for terms

In the portal, kubernetes services -> monitoring -> logs

Resource type -> kubernetes services -> "Find in ContainerLogV2"

Query:

```
// Find In ContainerLogV2
// Find in ContainerLogV2 to search for a specific value in the ContainerLogV2 table./nNote that this query requires updating the <SeachValue> parameter to produce results
// This query requires a parameter to run. Enter value in SearchValue to find in table.
let SearchValue =  "Processed";//Please update term you would like to find in the table.
ContainerLogV2
| where LogMessage contains tostring(SearchValue)
| take 7000
```


----------------------------------------

# Research notes:

## Accelerated networking:

### VMs

- https://learn.microsoft.com/en-us/azure/virtual-network/accelerated-networking-overview?tabs=ubuntu
- https://learn.microsoft.com/en-us/azure/virtual-network/accelerated-networking-how-it-works
- https://learn.microsoft.com/en-us/azure/virtual-network/accelerated-networking-mana-linux

## AKS nodes:

- https://alwaysupalwayson.blogspot.com/2018/08/accelerated-networking-enabled-by.html
  - `az network nic show -g <resource-group-where-the-nic-is> -n <nic-name> --query "enableAcceleratedNetworking"`
- https://github.com/Azure/AKS/issues/366
  - "AKS Team (Product Manager, Microsoft Azure) responded · November 13, 2018 This is now enabled automatically in AKS for supported VM SKUs."
- https://www.kristhecodingunicorn.com/post/aks-nodes-accelerated-networking/

## Proximity placement groups:

### VMs

- https://learn.microsoft.com/en-us/azure/virtual-machines/co-location
- https://microsoft.github.io/AzureTipsAndTricks/blog/tip226.html

## AKS nodes:

- https://learn.microsoft.com/en-us/azure/aks/reduce-latency-ppg


-------------------------------------------------------------------------------
# NOTES:

## Infrastructure automation tools

- Azure overview: https://learn.microsoft.com/en-us/azure/virtual-machines/infrastructure-automation

- Bicep: https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/
- Terraform: https://learn.microsoft.com/en-us/azure/developer/terraform/
- ARM Templates: JSON based, easier to use Bicep which "compiles" down to this.
- Docker compose:
    - https://learn.microsoft.com/en-us/azure/container-instances/tutorial-docker-compose
    - https://docs.docker.com/compose/compose-file/05-services/#scale

## Azure CLI

- https://learn.microsoft.com/en-us/cli/azure/install-azure-cli

Login to Azure and set up credentials for terraform:

```
$ az login
A web browser has been opened at https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize. Please continue the login in the web browser. If no web browser is available or if the web browser fails to open, use device code flow with `az login --use-device-code`.
[
  {
    "cloudName": "AzureCloud",
    "homeTenantId": "<tenantId>",
    "id": "<subscriptionId>",
    "isDefault": true,
    "managedByTenants": [],
    "name": "<subscription name>",
    "state": "Enabled",
    "tenantId": "<tenantId>",
    "user": {
      "name": "<email address>",
      "type": "user"
    }
  }
]

$ az account set --subscription "<subscriptionId>"
$ az ad sp create-for-rbac --role="Contributor" --scopes="/subscriptions/<subscriptionId>"
Creating 'Contributor' role assignment under scope '/subscriptions/<subscriptionId>'
The output includes credentials that you must protect. Be sure that you do not include these credentials in your code or check the credentials into your source control. For more information, see https://aka.ms/azadsp-cli
{
  "appId": "<appId>",
  "displayName": "azure-cli-2024-03-29-15-15-53",
  "password": "<password>",
  "tenant": "<tenantId>"
}

$ export ARM_CLIENT_ID="<appId>"
$ export ARM_CLIENT_SECRET="<password>"
$ export ARM_SUBSCRIPTION_ID="<subscriptionId>"
$ export ARM_TENANT_ID="<tenantId>"


# check expiration of login
az account get-access-token
```

### look at service bus:

```
az servicebus queue show --resource-group $AZURE_ANIMAL-rg \
    --namespace-name $AZURE_ANIMAL-service-bus \
    --name $AZURE_ANIMAL-queue \
    --query countDetails
```

## AKS

Ref:

- vm_size: https://learn.microsoft.com/en-us/azure/virtual-machines/sizes
   - defined in aks-cluster.tf.

List AKS clusters:

```
az aks list
```

Setup to use `kubectl`:

```
export KUBECONFIG="${PWD}/kubeconfig"
```

View nodes:

```
kubectl get nodes
```

#if export isn't done: `kubectl get nodes --kubeconfig kubeconfig


### bring up the stack:

```
terraform init -upgrade
terraform validate
terraform plan -out main.tfplan
terraform apply main.tfplan
```

### bring up loaders:

#### export the env vars from the terraform:

```
terraform output -json | jq -r '@sh "export AZURE_ANIMAL=\(.AZURE_ANIMAL.value)\nexport SENZING_AZURE_QUEUE_CONNECTION_STRING=\(.SENZING_AZURE_QUEUE_CONNECTION_STRING.value)\nexport SENZING_AZURE_QUEUE_NAME=\(.SENZING_AZURE_QUEUE_NAME.value)\nexport SENZING_DB_PWD=\(.db_admin_password.value)\nexport SENZING_ENGINE_CONFIGURATION_JSON=\(.SENZING_ENGINE_CONFIGURATION_JSON.value| gsub("[ \\n\\t]"; ""))"' > env.sh

source env.sh
```

envsubst < init-tools-deployment.yaml | kubectl apply -f -

#### deploy loaders:

```
envsubst < loader-deployment.yaml | kubectl apply -f -

# kubectl apply -f loader-deployment.yaml
```


#### other commands:

```
kubectl get pods --watch
kubectl get pod <pod name>
kubectl logs <pod_name>
kubectl logs -f <pod_name>
kubectl exec --stdin --tty <pod name> -- /bin/bash
kubectl get deployment
kubectl delete deployment <deployment name>
```

#### search logs for terms

In the portal, kubernetes services -> monitoring -> logs

Resource type -> kubernetes services -> "Find in ContainerLogV2"

Query:

```
// Find In ContainerLogV2
// Find in ContainerLogV2 to search for a specific value in the ContainerLogV2 table./nNote that this query requires updating the <SeachValue> parameter to produce results
// This query requires a parameter to run. Enter value in SearchValue to find in table.
let SearchValue =  "Processed";//Please update term you would like to find in the table.
ContainerLogV2
| where LogMessage contains tostring(SearchValue)
| take 7000
```

#### looking inside a consumer:

##### if you need to work with the database from the consumer:

- from local: `terraform output -json | jq -r ".db_admin_password.value"`
- exec into pod: `kubectl exec --stdin --tty <pod name> -- /bin/bash`
- inside pod: `export SENZING_DB_PWD=<pwd>`

##### other useful tooling for inside the consumer pod:

```
# install some tools:
apt update && apt install -y procps gdb less net-tools

# take a look with gdb:
gdb -p $(ps aux|grep python3 |grep -v grep|awk '{ print $2 }') -batch -ex 'thread apply all bt' > dump.out
grep -P ':\d+$' dump.out | grep ' in ' | awk 'function basename(file, a, n) {
    n = split(file, a, "/")
    return a[n]
  }
{print $1" "$4" ",basename($NF)}' > summary.out

awk '{print $2}' summary.out | sort | uniq -c | sort -n

```

#### ref:
- https://spacelift.io/blog/kubectl-delete-deployment
- https://spacelift.io/blog/kubectl-delete-pod
- https://spacelift.io/blog/kubectl-logs


### See logs of a container app:

- Ref: https://learn.microsoft.com/en-us/cli/azure/containerapp/logs?view=azure-cli-latest

```
# assumes: export AZURE_ANIMAL=sz-sensible-dodo
az containerapp logs show --resource-group $AZURE_ANIMAL-rg --name $AZURE_ANIMAL-init-db-ca --follow
az containerapp logs show --resource-group $AZURE_ANIMAL-rg --name $AZURE_ANIMAL-init-db-ca --container $AZURE_ANIMAL-init-database
az containerapp logs show --resource-group $AZURE_ANIMAL-rg --name $AZURE_ANIMAL-init-db-ca --container $AZURE_ANIMAL-senzing-producer
```

### Attach to running container in a container app:

```
# assumes: export AZURE_ANIMAL=sz-first-termite
az containerapp exec --name $AZURE_ANIMAL-init-db-ca --resource-group $AZURE_ANIMAL-rg --command bash --container $AZURE_ANIMAL-senzingapi-tools
az containerapp exec --name $AZURE_ANIMAL-init-db-ca --resource-group $AZURE_ANIMAL-rg --command bash --container $AZURE_ANIMAL-init-database
```


### Database

- az database commands: https://learn.microsoft.com/en-us/cli/azure/sql/db?view=azure-cli-latest
- SKUs: https://learn.microsoft.com/en-us/dotnet/api/azure.resourcemanager.sql.sqldatabasedata.sku?view=azure-dotnet


#### get the database config [default database config](#default-database-config)

- ref: https://learn.microsoft.com/en-us/cli/azure/sql/db?view=azure-cli-latest#az-sql-db-show

```
export AZURE_ANIMAL=sz-exciting-hawk
az sql db show --name G2 --resource-group $AZURE_ANIMAL-rg --server $AZURE_ANIMAL-mssql-server
```

#### available SKUs [Westus list](#available-skus-for-westus)

```
az sql db list-editions -l westus -o table
```

#### inside senzing container:

```
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "ALTER DATABASE G2 SET DELAYED_DURABILITY = Forced;"
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "ALTER DATABASE G2 SET AUTO_UPDATE_STATISTICS_ASYNC ON;"
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "ALTER DATABASE G2 SET AUTO_CREATE_STATISTICS ON;"
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 1;"

# MAXDOP ref: https://www.sqlshack.com/configure-the-max-degree-of-parallelism-maxdop-in-azure-sql-database/

### make sure the above worked:
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "select delayed_durability, delayed_durability_desc, is_auto_create_stats_on, is_auto_update_stats_on from sys.databases;"

sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "SELECT [value] as CurrentMAXDOP FROM sys.database_scoped_configurations WHERE [name] = 'MAXDOP';"


sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "select * from sys.database_scoped_configurations;"
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "select * from sys.databases;"


sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "SELECT name FROM sys.tables;"
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -i /tmp/q.sql -o /tmp/q.out
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "SELECT * FROM sys_vars"

sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "SELECT GETDATE(), COUNT(*) FROM DSRC_RECORD;"
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "SELECT GETDATE(), COUNT(*) FROM OBS_ENT;"
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "SELECT GETDATE(), COUNT(*) FROM RES_ENT;"
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "SELECT GETDATE(), COUNT(*) FROM RES_ENT_OKEY;"
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "SELECT GETDATE(), COUNT(*) FROM SYS_EVAL_QUEUE;"
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "SELECT GETDATE(), COUNT(*) FROM RES_RELATE;"


# query that is close to what the AWS query gives us
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "select min(first_seen_dt) load_start, count(*)/(DATEDIFF_BIG(SECOND, min(first_seen_dt), max(first_seen_dt))/60) erpm, count(*) total, max(first_seen_dt)-min(first_seen_dt) duration, count(*)/DATEDIFF_BIG(SECOND, min(first_seen_dt), max(first_seen_dt)) avg_erps from dsrc_record;"

# from the perf page limited to last hour
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "select min(FIRST_SEEN_DT) load_start, count(*) / (DATEDIFF(s,min(FIRST_SEEN_DT),max(FIRST_SEEN_DT))/60) erpm, count(*) total, DATEDIFF(mi,min(FIRST_SEEN_DT),max(FIRST_SEEN_DT))/(60.0*24.0) duration from DSRC_RECORD WITH (NOLOCK) where FIRST_SEEN_DT > DATEADD(hh, -1, GETDATE());"

# same query, but not limited:
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -Q 'select min(FIRST_SEEN_DT) load_start, count(*) / (DATEDIFF(s,min(FIRST_SEEN_DT),max(FIRST_SEEN_DT))/60) erpm, count(*) total, DATEDIFF(mi,min(FIRST_SEEN_DT),max(FIRST_SEEN_DT))/(60.0*24.0) duration from DSRC_RECORD WITH (NOLOCK);'

# extra queries that brian wants run
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "select dr.RECORD_ID,oe.OBS_ENT_ID,reo.RES_ENT_ID from DSRC_RECORD dr left outer join OBS_ENT oe ON dr.dsrc_id = oe.dsrc_id and dr.ent_src_key = oe.ent_src_key left outer join RES_ENT_OKEY reo ON oe.OBS_ENT_ID = reo.OBS_ENT_ID where reo.RES_ENT_ID is null;"
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "select dr.RECORD_ID,reo.OBS_ENT_ID,reo.RES_ENT_ID from RES_ENT_OKEY reo left outer join OBS_ENT oe ON oe.OBS_ENT_ID = reo.OBS_ENT_ID  left outer join DSRC_RECORD dr  ON dr.dsrc_id = oe.dsrc_id and dr.ent_src_key = oe.ent_src_key where dr.RECORD_ID is null;"
```



```
isql "DRIVER={ODBC Driver 17 for SQL Server}; SERVER=$AZURE_ANIMAL-mssql-server.database.windows.net; DATABASE=G2; PORT=1433; UID=senzing; PWD=$SENZING_DB_PWD" -v

isql "Driver={ODBC Driver 17 for SQL Server};Server=tcp:sz-closing-dory-mssql-server.database.windows.net,1433;Database=G2;Uid=senzing;Pwd=mJz4U5FTfAx9wsSR3kJ9;Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;" -v

# queries from the perf page:
--- Currently waiting
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "select sqltext, CAST (STRING_AGG(wait_type, \"|\") as varchar(50)), sum(cnt) as cnt, sum(elapsed) as elapsed from (SELECT sqltext.TEXT as sqltext,req.wait_type as wait_type,count(*) as cnt, sum(req.total_elapsed_time) elapsed FROM sys.dm_exec_requests req CROSS APPLY sys.dm_exec_sql_text(sql_handle) AS sqltext where wait_type is not NULL group by sqltext.TEXT, req.wait_type having count(*)>1) a group by a.sqltext order by 3 desc;"
GO
--- Transactions per minute for the entire repository (doesn't count updates)
--- light dimming, limited to last hour
select CUR_MINUTE as timegroup, count(*) from (select CONVERT(VARCHAR,DATEADD(s,ROUND(DATEDIFF(s,'1970-01-01 00:00:00',FIRST_SEEN_DT)/60,0)*60,'1970-01-01 00:00:00'),20) as CUR_MINUTE from DSRC_RECORD WITH (NOLOCK) where FIRST_SEEN_DT > DATEADD(hh, -1, GETDATE())) a group by CUR_MINUTE order by CUR_MINUTE ASC;
GO
--- Entire historical overall perf (only good for single large batch loads), could add where FIRST_SEEN_DT > ? to limit it to recent
--- light dimming, limited to last hour
select min(FIRST_SEEN_DT) load_start, count(*) / (DATEDIFF(s,min(FIRST_SEEN_DT),max(FIRST_SEEN_DT))/60) erpm, count(*) total, DATEDIFF(mi,min(FIRST_SEEN_DT),max(FIRST_SEEN_DT))/(60.0*24.0) duration from DSRC_RECORD WITH (NOLOCK) where FIRST_SEEN_DT > DATEADD(hh, -1, GETDATE());

```

## Azure logs

Container app > Monitoring > Logs (instead of log stream)

```
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == 'sz-proud-arachnid-ca'
| project Time=TimeGenerated, AppName=ContainerAppName_s, Revision=RevisionName_s, Container=ContainerName_s, Message=Log_s
| take 100
```

```
ContainerAppSystemLogs_CL
| where ContainerAppName_s == 'sz-proud-arachnid-ca'
| project Time=TimeGenerated, EnvName=EnvironmentName_s, AppName=ContainerAppName_s, Revision=RevisionName_s, Message=Log_s
| take 100
```

## Terraform

To create the resources, in the `perf.tf` directory:

```
terraform init -upgrade
terraform validate
terraform plan -out main.tfplan
terraform apply main.tfplan
```

Get the sensitive outputs from the terraform plan:

```
terraform output -json | jq -r ".db_admin_password.value"
terraform output -json | jq -r ".queue_connection_string.value"
```

Other terraform things to play with:

```
resource_group_name=$(terraform output -raw resource_group_name)
az group show --name $resource_group_name

terraform show -json main.tfplan

```

To destroy the resources, in the `perf.tf` directory:

```
terraform plan -destroy -out main.destroy.tfplan
terraform apply main.destroy.tfplan
```

## Azure queue

sub-command for stream producer: gzipped-json-to-azure-queue

terraform import azurerm_servicebus_namespace.example /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mygroup1/providers/Microsoft.ServiceBus/namespaces/sbns1


Host name: sz-welcome-turtle-service-bus.servicebus.windows.net
"serviceBusEndpoint": "https://sz-welcome-turtle-service-bus.servicebus.windows.net:443/",
"id": "/subscriptions/5415bf99-6956-43fd-a8a9-434c958ca13c/resourceGroups/sz-welcome-turtle-rg/providers/Microsoft.ServiceBus/namespaces/sz-welcome-turtle-service-bus",


## References:

- terraform on azure: https://learn.microsoft.com/en-us/azure/developer/terraform/
- resource group creation: https://learn.microsoft.com/en-us/azure/developer/terraform/create-resource-group?tabs=azure-cli
    - left panel lists other resources and howtos of interest

#### environment variables:

Terraform can directly access environment variables that are named using the pattern TF_VAR_, for example TF_VAR_foo=bar will provide the value bar to the variable declared using variable "foo" {}

Ref. https://support.hashicorp.com/hc/en-us/articles/4547786359571-Reading-and-using-environment-variables-in-Terraform-runs

## sqlcmd

- https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-setup-tools?view=sql-server-ver16&tabs=redhat-install
- https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-utility?view=sql-server-ver16&tabs=go%2Cmac&pivots=cs1-bash

### Install using brew:

- https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-setup-tools?view=sql-server-ver16&tabs=redhat-install

```
brew tap microsoft/mssql-release https://github.com/Microsoft/homebrew-mssql-release
brew update
brew install mssql-tools18
```

### Using sqlcmd:

- https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-utility?view=sql-server-ver16&tabs=go%2Cwindows&pivots=cs1-bash

```
export SQLCMDPASSWORD=$(terraform output -json | jq -r ".db_admin_password.value")
sqlcmd -Ssenzing-sql-server.database.windows.net -dG2 -Usenzing
1> select @@version
2> go
```

Note: must always use "go" to execute the sql command. Use "exit" to quit sqlcmd.


----------------------------------------

#### default database config

```
az sql db show --name G2 --resource-group sz-possible-filly-rg --server sz-possible-filly-mssql-server

{
  "autoPauseDelay": null,
  "availabilityZone": "NoPreference",
  "catalogCollation": "SQL_Latin1_General_CP1_CI_AS",
  "collation": "SQL_Latin1_General_CP1_CI_AS",
  "createMode": null,
  "creationDate": "2024-04-01T18:03:45.370000+00:00",
  "currentBackupStorageRedundancy": "Geo",
  "currentServiceObjectiveName": "GP_Gen5_2",
  "currentSku": {
    "capacity": 2,
    "family": "Gen5",
    "name": "GP_Gen5",
    "size": null,
    "tier": "GeneralPurpose"
  },
  "databaseId": "46a52e52-b901-4d45-ae43-9b531037bcf2",
  "defaultSecondaryLocation": "eastus",
  "earliestRestoreDate": null,
  "edition": "GeneralPurpose",
  "elasticPoolId": null,
  "elasticPoolName": null,
  "encryptionProtector": null,
  "encryptionProtectorAutoRotation": null,
  "failoverGroupId": null,
  "federatedClientId": null,
  "freeLimitExhaustionBehavior": null,
  "highAvailabilityReplicaCount": null,
  "id": "/subscriptions/5415bf99-6956-43fd-a8a9-434c958ca13c/resourceGroups/sz-possible-filly-rg/providers/Microsoft.Sql/servers/sz-possible-filly-mssql-server/databases/G2",
  "identity": null,
  "isInfraEncryptionEnabled": false,
  "keys": null,
  "kind": "v12.0,user,vcore",
  "ledgerOn": false,
  "licenseType": "LicenseIncluded",
  "location": "westus",
  "longTermRetentionBackupResourceId": null,
  "maintenanceConfigurationId": "/subscriptions/5415bf99-6956-43fd-a8a9-434c958ca13c/providers/Microsoft.Maintenance/publicMaintenanceConfigurations/SQL_Default",
  "managedBy": null,
  "manualCutover": null,
  "maxLogSizeBytes": 193273528320,
  "maxSizeBytes": 34359738368,
  "minCapacity": null,
  "name": "G2",
  "pausedDate": null,
  "performCutover": null,
  "preferredEnclaveType": "Default",
  "readScale": "Disabled",
  "recoverableDatabaseId": null,
  "recoveryServicesRecoveryPointId": null,
  "requestedBackupStorageRedundancy": "Geo",
  "requestedServiceObjectiveName": "GP_Gen5_2",
  "resourceGroup": "sz-possible-filly-rg",
  "restorableDroppedDatabaseId": null,
  "restorePointInTime": null,
  "resumedDate": null,
  "sampleName": null,
  "secondaryType": null,
  "sku": {
    "capacity": 2,
    "family": "Gen5",
    "name": "GP_Gen5",
    "size": null,
    "tier": "GeneralPurpose"
  },
  "sourceDatabaseDeletionDate": null,
  "sourceDatabaseId": null,
  "sourceResourceId": null,
  "status": "Online",
  "tags": {},
  "type": "Microsoft.Sql/servers/databases",
  "useFreeLimit": null,
  "zoneRedundant": false
}
```

#### Available SKUs for westus

```
$ az sql db list-editions -l westus -o table

ServiceObjective    Sku            Edition           Family    Capacity    Unit    Available
------------------  -------------  ----------------  --------  ----------  ------  -----------
System              System         System                      0           DTU     False
System0             System         System                      0           DTU     False
System1             System         System                      0           DTU     False
System2             System         System                      0           DTU     False
System3             System         System                      0           DTU     False
System4             System         System                      0           DTU     False
System2L            System         System                      0           DTU     False
System3L            System         System                      0           DTU     False
System4L            System         System                      0           DTU     False
GP_SYSTEM_2         GP_SYSTEM      System            Gen5      2           VCores  False
GP_SYSTEM_4         GP_SYSTEM      System            Gen5      4           VCores  False
GP_SYSTEM_8         GP_SYSTEM      System            Gen5      8           VCores  False
Free                Free           Free                        5           DTU     True
Basic               Basic          Basic                       5           DTU     True
S0                  Standard       Standard                    10          DTU     True
S1                  Standard       Standard                    20          DTU     True
S2                  Standard       Standard                    50          DTU     True
S3                  Standard       Standard                    100         DTU     True
S4                  Standard       Standard                    200         DTU     True
S6                  Standard       Standard                    400         DTU     True
S7                  Standard       Standard                    800         DTU     True
S9                  Standard       Standard                    1600        DTU     True
S12                 Standard       Standard                    3000        DTU     True
P1                  Premium        Premium                     125         DTU     True
P2                  Premium        Premium                     250         DTU     True
P4                  Premium        Premium                     500         DTU     True
P6                  Premium        Premium                     1000        DTU     True
P11                 Premium        Premium                     1750        DTU     True
P15                 Premium        Premium                     4000        DTU     True
DW100c              DataWarehouse  DataWarehouse               900         DTU     True
DW200c              DataWarehouse  DataWarehouse               1800        DTU     True
DW300c              DataWarehouse  DataWarehouse               2700        DTU     True
DW400c              DataWarehouse  DataWarehouse               3600        DTU     True
DW500c              DataWarehouse  DataWarehouse               4500        DTU     True
DW1000c             DataWarehouse  DataWarehouse               9000        DTU     True
DW1500c             DataWarehouse  DataWarehouse               13500       DTU     True
DW2000c             DataWarehouse  DataWarehouse               18000       DTU     True
DW2500c             DataWarehouse  DataWarehouse               22500       DTU     True
DW3000c             DataWarehouse  DataWarehouse               27000       DTU     True
DW5000c             DataWarehouse  DataWarehouse               45000       DTU     True
DW6000c             DataWarehouse  DataWarehouse               54000       DTU     True
DW7500c             DataWarehouse  DataWarehouse               67500       DTU     True
DW10000c            DataWarehouse  DataWarehouse               90000       DTU     True
DW15000c            DataWarehouse  DataWarehouse               135000      DTU     True
DW30000c            DataWarehouse  DataWarehouse               270000      DTU     True
DS100               Stretch        Stretch                     750         DTU     True
DS200               Stretch        Stretch                     1500        DTU     True
DS300               Stretch        Stretch                     2250        DTU     True
DS400               Stretch        Stretch                     3000        DTU     True
DS500               Stretch        Stretch                     3750        DTU     True
DS600               Stretch        Stretch                     4500        DTU     True
DS1000              Stretch        Stretch                     7500        DTU     True
DS1200              Stretch        Stretch                     9000        DTU     True
DS1500              Stretch        Stretch                     11250       DTU     True
DS2000              Stretch        Stretch                     15000       DTU     True
GP_S_Gen5_1         GP_S_Gen5      GeneralPurpose    Gen5      1           VCores  True
GP_Gen5_2           GP_Gen5        GeneralPurpose    Gen5      2           VCores  True
GP_S_Gen5_2         GP_S_Gen5      GeneralPurpose    Gen5      2           VCores  True
GP_DC_2             GP_DC          GeneralPurpose    DC        2           VCores  True
GP_Gen5_4           GP_Gen5        GeneralPurpose    Gen5      4           VCores  True
GP_S_Gen5_4         GP_S_Gen5      GeneralPurpose    Gen5      4           VCores  True
GP_DC_4             GP_DC          GeneralPurpose    DC        4           VCores  True
GP_Gen5_6           GP_Gen5        GeneralPurpose    Gen5      6           VCores  True
GP_S_Gen5_6         GP_S_Gen5      GeneralPurpose    Gen5      6           VCores  True
GP_DC_6             GP_DC          GeneralPurpose    DC        6           VCores  True
GP_Gen5_8           GP_Gen5        GeneralPurpose    Gen5      8           VCores  True
GP_S_Gen5_8         GP_S_Gen5      GeneralPurpose    Gen5      8           VCores  True
GP_DC_8             GP_DC          GeneralPurpose    DC        8           VCores  True
GP_Gen5_10          GP_Gen5        GeneralPurpose    Gen5      10          VCores  True
GP_S_Gen5_10        GP_S_Gen5      GeneralPurpose    Gen5      10          VCores  True
GP_DC_10            GP_DC          GeneralPurpose    DC        10          VCores  True
GP_Gen5_12          GP_Gen5        GeneralPurpose    Gen5      12          VCores  True
GP_S_Gen5_12        GP_S_Gen5      GeneralPurpose    Gen5      12          VCores  True
GP_DC_12            GP_DC          GeneralPurpose    DC        12          VCores  True
GP_Gen5_14          GP_Gen5        GeneralPurpose    Gen5      14          VCores  True
GP_S_Gen5_14        GP_S_Gen5      GeneralPurpose    Gen5      14          VCores  True
GP_DC_14            GP_DC          GeneralPurpose    DC        14          VCores  True
GP_Gen5_16          GP_Gen5        GeneralPurpose    Gen5      16          VCores  True
GP_S_Gen5_16        GP_S_Gen5      GeneralPurpose    Gen5      16          VCores  True
GP_DC_16            GP_DC          GeneralPurpose    DC        16          VCores  True
GP_Gen5_18          GP_Gen5        GeneralPurpose    Gen5      18          VCores  True
GP_S_Gen5_18        GP_S_Gen5      GeneralPurpose    Gen5      18          VCores  True
GP_DC_18            GP_DC          GeneralPurpose    DC        18          VCores  True
GP_Gen5_20          GP_Gen5        GeneralPurpose    Gen5      20          VCores  True
GP_S_Gen5_20        GP_S_Gen5      GeneralPurpose    Gen5      20          VCores  True
GP_DC_20            GP_DC          GeneralPurpose    DC        20          VCores  True
GP_Gen5_24          GP_Gen5        GeneralPurpose    Gen5      24          VCores  True
GP_S_Gen5_24        GP_S_Gen5      GeneralPurpose    Gen5      24          VCores  True
GP_Gen5_32          GP_Gen5        GeneralPurpose    Gen5      32          VCores  True
GP_S_Gen5_32        GP_S_Gen5      GeneralPurpose    Gen5      32          VCores  True
GP_DC_32            GP_DC          GeneralPurpose    DC        32          VCores  True
GP_Gen5_40          GP_Gen5        GeneralPurpose    Gen5      40          VCores  True
GP_S_Gen5_40        GP_S_Gen5      GeneralPurpose    Gen5      40          VCores  True
GP_DC_40            GP_DC          GeneralPurpose    DC        40          VCores  True
GP_Gen5_80          GP_Gen5        GeneralPurpose    Gen5      80          VCores  True
GP_S_Gen5_80        GP_S_Gen5      GeneralPurpose    Gen5      80          VCores  True
GP_Gen5_128         GP_Gen5        GeneralPurpose    Gen5      128         VCores  True
BC_Gen5_2           BC_Gen5        BusinessCritical  Gen5      2           VCores  True
BC_DC_2             BC_DC          BusinessCritical  DC        2           VCores  True
BC_Gen5_4           BC_Gen5        BusinessCritical  Gen5      4           VCores  True
BC_DC_4             BC_DC          BusinessCritical  DC        4           VCores  True
BC_Gen5_6           BC_Gen5        BusinessCritical  Gen5      6           VCores  True
BC_DC_6             BC_DC          BusinessCritical  DC        6           VCores  True
BC_Gen5_8           BC_Gen5        BusinessCritical  Gen5      8           VCores  True
BC_DC_8             BC_DC          BusinessCritical  DC        8           VCores  True
BC_Gen5_10          BC_Gen5        BusinessCritical  Gen5      10          VCores  True
BC_DC_10            BC_DC          BusinessCritical  DC        10          VCores  True
BC_Gen5_12          BC_Gen5        BusinessCritical  Gen5      12          VCores  True
BC_DC_12            BC_DC          BusinessCritical  DC        12          VCores  True
BC_Gen5_14          BC_Gen5        BusinessCritical  Gen5      14          VCores  True
BC_DC_14            BC_DC          BusinessCritical  DC        14          VCores  True
BC_Gen5_16          BC_Gen5        BusinessCritical  Gen5      16          VCores  True
BC_DC_16            BC_DC          BusinessCritical  DC        16          VCores  True
BC_Gen5_18          BC_Gen5        BusinessCritical  Gen5      18          VCores  True
BC_DC_18            BC_DC          BusinessCritical  DC        18          VCores  True
BC_Gen5_20          BC_Gen5        BusinessCritical  Gen5      20          VCores  True
BC_DC_20            BC_DC          BusinessCritical  DC        20          VCores  True
BC_Gen5_24          BC_Gen5        BusinessCritical  Gen5      24          VCores  True
BC_Gen5_32          BC_Gen5        BusinessCritical  Gen5      32          VCores  True
BC_DC_32            BC_DC          BusinessCritical  DC        32          VCores  True
BC_Gen5_40          BC_Gen5        BusinessCritical  Gen5      40          VCores  True
BC_DC_40            BC_DC          BusinessCritical  DC        40          VCores  True
BC_Gen5_80          BC_Gen5        BusinessCritical  Gen5      80          VCores  True
BC_Gen5_128         BC_Gen5        BusinessCritical  Gen5      128         VCores  True
HS_Gen5_2           HS_Gen5        Hyperscale        Gen5      2           VCores  True
HS_S_Gen5_2         HS_S_Gen5      Hyperscale        Gen5      2           VCores  True
HS_PRMS_2           HS_PRMS        Hyperscale        8IM       2           VCores  True
HS_MOPRMS_2         HS_MOPRMS      Hyperscale        8IH       2           VCores  True
HS_DC_2             HS_DC          Hyperscale        DC        2           VCores  True
HS_Gen5_4           HS_Gen5        Hyperscale        Gen5      4           VCores  True
HS_S_Gen5_4         HS_S_Gen5      Hyperscale        Gen5      4           VCores  True
HS_PRMS_4           HS_PRMS        Hyperscale        8IM       4           VCores  True
HS_MOPRMS_4         HS_MOPRMS      Hyperscale        8IH       4           VCores  True
HS_DC_4             HS_DC          Hyperscale        DC        4           VCores  True
HS_Gen5_6           HS_Gen5        Hyperscale        Gen5      6           VCores  True
HS_S_Gen5_6         HS_S_Gen5      Hyperscale        Gen5      6           VCores  True
HS_PRMS_6           HS_PRMS        Hyperscale        8IM       6           VCores  True
HS_MOPRMS_6         HS_MOPRMS      Hyperscale        8IH       6           VCores  True
HS_DC_6             HS_DC          Hyperscale        DC        6           VCores  True
HS_Gen5_8           HS_Gen5        Hyperscale        Gen5      8           VCores  True
HS_S_Gen5_8         HS_S_Gen5      Hyperscale        Gen5      8           VCores  True
HS_PRMS_8           HS_PRMS        Hyperscale        8IM       8           VCores  True
HS_MOPRMS_8         HS_MOPRMS      Hyperscale        8IH       8           VCores  True
HS_DC_8             HS_DC          Hyperscale        DC        8           VCores  True
HS_Gen5_10          HS_Gen5        Hyperscale        Gen5      10          VCores  True
HS_S_Gen5_10        HS_S_Gen5      Hyperscale        Gen5      10          VCores  True
HS_PRMS_10          HS_PRMS        Hyperscale        8IM       10          VCores  True
HS_MOPRMS_10        HS_MOPRMS      Hyperscale        8IH       10          VCores  True
HS_DC_10            HS_DC          Hyperscale        DC        10          VCores  True
HS_Gen5_12          HS_Gen5        Hyperscale        Gen5      12          VCores  True
HS_S_Gen5_12        HS_S_Gen5      Hyperscale        Gen5      12          VCores  True
HS_PRMS_12          HS_PRMS        Hyperscale        8IM       12          VCores  True
HS_MOPRMS_12        HS_MOPRMS      Hyperscale        8IH       12          VCores  True
HS_DC_12            HS_DC          Hyperscale        DC        12          VCores  True
HS_Gen5_14          HS_Gen5        Hyperscale        Gen5      14          VCores  True
HS_S_Gen5_14        HS_S_Gen5      Hyperscale        Gen5      14          VCores  True
HS_PRMS_14          HS_PRMS        Hyperscale        8IM       14          VCores  True
HS_MOPRMS_14        HS_MOPRMS      Hyperscale        8IH       14          VCores  True
HS_DC_14            HS_DC          Hyperscale        DC        14          VCores  True
HS_Gen5_16          HS_Gen5        Hyperscale        Gen5      16          VCores  True
HS_S_Gen5_16        HS_S_Gen5      Hyperscale        Gen5      16          VCores  True
HS_PRMS_16          HS_PRMS        Hyperscale        8IM       16          VCores  True
HS_MOPRMS_16        HS_MOPRMS      Hyperscale        8IH       16          VCores  True
HS_DC_16            HS_DC          Hyperscale        DC        16          VCores  True
HS_Gen5_18          HS_Gen5        Hyperscale        Gen5      18          VCores  True
HS_S_Gen5_18        HS_S_Gen5      Hyperscale        Gen5      18          VCores  True
HS_PRMS_18          HS_PRMS        Hyperscale        8IM       18          VCores  True
HS_MOPRMS_18        HS_MOPRMS      Hyperscale        8IH       18          VCores  True
HS_DC_18            HS_DC          Hyperscale        DC        18          VCores  True
HS_Gen5_20          HS_Gen5        Hyperscale        Gen5      20          VCores  True
HS_S_Gen5_20        HS_S_Gen5      Hyperscale        Gen5      20          VCores  True
HS_PRMS_20          HS_PRMS        Hyperscale        8IM       20          VCores  True
HS_MOPRMS_20        HS_MOPRMS      Hyperscale        8IH       20          VCores  True
HS_DC_20            HS_DC          Hyperscale        DC        20          VCores  True
HS_Gen5_24          HS_Gen5        Hyperscale        Gen5      24          VCores  True
HS_S_Gen5_24        HS_S_Gen5      Hyperscale        Gen5      24          VCores  True
HS_PRMS_24          HS_PRMS        Hyperscale        8IM       24          VCores  True
HS_MOPRMS_24        HS_MOPRMS      Hyperscale        8IH       24          VCores  True
HS_Gen5_32          HS_Gen5        Hyperscale        Gen5      32          VCores  True
HS_S_Gen5_32        HS_S_Gen5      Hyperscale        Gen5      32          VCores  True
HS_PRMS_32          HS_PRMS        Hyperscale        8IM       32          VCores  True
HS_MOPRMS_32        HS_MOPRMS      Hyperscale        8IH       32          VCores  True
HS_DC_32            HS_DC          Hyperscale        DC        32          VCores  True
HS_Gen5_40          HS_Gen5        Hyperscale        Gen5      40          VCores  True
HS_S_Gen5_40        HS_S_Gen5      Hyperscale        Gen5      40          VCores  True
HS_PRMS_40          HS_PRMS        Hyperscale        8IM       40          VCores  True
HS_MOPRMS_40        HS_MOPRMS      Hyperscale        8IH       40          VCores  True
HS_DC_40            HS_DC          Hyperscale        DC        40          VCores  True
HS_PRMS_64          HS_PRMS        Hyperscale        8IM       64          VCores  True
HS_MOPRMS_64        HS_MOPRMS      Hyperscale        8IH       64          VCores  True
HS_Gen5_80          HS_Gen5        Hyperscale        Gen5      80          VCores  True
HS_S_Gen5_80        HS_S_Gen5      Hyperscale        Gen5      80          VCores  True
HS_PRMS_80          HS_PRMS        Hyperscale        8IM       80          VCores  True
HS_MOPRMS_80        HS_MOPRMS      Hyperscale        8IH       80          VCores  True
HS_PRMS_128         HS_PRMS        Hyperscale        8IM       128         VCores  True
```





## set up Senzing container:

- REF: https://learn.microsoft.com/en-us/sql/connect/odbc/linux-mac/installing-the-microsoft-odbc-driver-for-sql-server?view=sql-server-ver16&tabs=debian18-install%2Cdebian17-install%2Cdebian8-install%2Credhat7-13-install%2Crhel7-offline

Assumes that two environment vars are set in the container:
- AZURE_ANIMAL = sz-random-animal # used to name all azure resources uniquely, including the database
- SENZING_DB_PWD = un-encoded database password.  used for the `sqlcmd` command

```
# install MS drivers and tools (tools are only needed IF initializing the database)
/bin/bash
wget -qO - https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.gpg \
&& wget -qO - https://packages.microsoft.com/config/debian/11/prod.list > /etc/apt/sources.list.d/mssql-release.list \
&& apt-get update \
&& ACCEPT_EULA=Y apt-get -y install msodbcsql18 \
&& ACCEPT_EULA=Y apt-get -y install mssql-tools18
echo 'export PATH="$PATH:/opt/mssql-tools18/bin"' >> ~/.bashrc
source ~/.bashrc

# Senzing database initialization

wget -qO ${SENZING_APT_REPOSITORY_NAME} ${SENZING_APT_REPOSITORY_URL}/${SENZING_APT_REPOSITORY_NAME} \
  && apt-get -y install ./${SENZING_APT_REPOSITORY_NAME}

apt-get update \
  && apt-get -y install senzingapi-setup


wget -qO - https://raw.githubusercontent.com/senzing-garage/init-database/main/rootfs/opt/senzing/g2/resources/schema/g2core-schema-mssql-create.sql > /tmp/g2core-schema-mssql-create.sql

sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -i /tmp/g2core-schema-mssql-create.sql -o /tmp/schema.out


sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -i /opt/senzing/g2/resources/schema/g2core-schema-mssql-create.sql -o /tmp/schema.out

echo "addDataSource CUSTOMERS" > /tmp/add.sz
echo "addDataSource REFERENCE" >> /tmp/add.sz
echo "addDataSource WATCHLIST" >> /tmp/add.sz
echo "save" >> /tmp/add.sz

G2ConfigTool.py -f /tmp/add.sz
```


```
{
            "PIPELINE": {
                "CONFIGPATH": "/etc/opt/senzing",
                "LICENSESTRINGBASE64": "{license_string}",
                "RESOURCEPATH": "/opt/senzing/g2/resources",
                "SUPPORTPATH": "/opt/senzing/data"
            },
            "SQL": {
                "BACKEND": "SQL",
                "CONNECTION" : "mssql://senzing:fsiPYFJ5Ee%7BDZm%3Fz%29%7B_h@sz-social-kit-mssql-server.database.windows.net:1433:G2"
            }
        }

export SENZING_ENGINE_CONFIGURATION_JSON='{"PIPELINE": {"CONFIGPATH": "/etc/opt/senzing","LICENSESTRINGBASE64": "{license_string}","RESOURCEPATH": "/opt/senzing/g2/resources","SUPPORTPATH": "/opt/senzing/data"},"SQL": {"BACKEND": "SQL","CONNECTION" : "mssql://senzing:fsiPYFJ5Ee%7BDZm%3Fz%29%7B_h@sz-social-kit-mssql-server.database.windows.net:1433:G2"} }'
```

