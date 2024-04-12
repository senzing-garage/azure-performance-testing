# azure-performance-testing

[Azure portal](http://portal.azure.com/)

## Infrastructure automation tools

- Azure overview: https://learn.microsoft.com/en-us/azure/virtual-machines/infrastructure-automation

- Bicep: https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/
- Terraform: https://learn.microsoft.com/en-us/azure/developer/terraform/
- ARM Templates: JSON based, easier to use Bicep which "compiles" down to this.
- Docker compose:
    - https://learn.microsoft.com/en-us/azure/container-instances/tutorial-docker-compose
    - https://docs.docker.com/compose/compose-file/05-services/#scale

## az - Azure CLI

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

## Azure container apps:

Total CPU and memory for all containers defined in a Container App must add up to one of the following CPU - Memory combinations:

- [cpu: 0.25, memory: 0.5Gi]
- [cpu: 0.5, memory: 1.0Gi]
- [cpu: 0.75, memory: 1.5Gi]
- [cpu: 1.0, memory: 2.0Gi]
- [cpu: 1.25, memory: 2.5Gi]
- [cpu: 1.5, memory: 3.0Gi]
- [cpu: 1.75, memory: 3.5Gi]
- [cpu: 2.0, memory: 4.0Gi]

### See logs of a container app:

- Ref: https://learn.microsoft.com/en-us/cli/azure/containerapp/logs?view=azure-cli-latest

```
export AZURE_ANIMAL=sz-sensible-dodo
az containerapp logs show --resource-group $AZURE_ANIMAL-rg --name $AZURE_ANIMAL-ca --follow
az containerapp logs show --resource-group $AZURE_ANIMAL-rg --name $AZURE_ANIMAL-ca --container $AZURE_ANIMAL-debian
```

### Attach to running container in a container app:

```
export AZURE_ANIMAL=sz-legal-antelope
az containerapp exec --name $AZURE_ANIMAL-ca --resource-group $AZURE_ANIMAL-rg --command bash --container $AZURE_ANIMAL-senzing-loader
az containerapp exec --name $AZURE_ANIMAL-init-db-ca --resource-group $AZURE_ANIMAL-rg --command bash --container $AZURE_ANIMAL-senzingapi-tools


wget -qO - https://raw.githubusercontent.com/roncewind/sz_sb_consumer/main/test.py > /app/test.py


export SENZING_ENGINE_CONFIGURATION_JSON='{"PIPELINE": {"CONFIGPATH": "/etc/opt/senzing","LICENSESTRINGBASE64": "{license_string}","RESOURCEPATH": "/opt/senzing/g2/resources","SUPPORTPATH": "/opt/senzing/data"},"SQL": {"BACKEND": "SQL","DEBUGLEVEL": "","CONNECTION" : "mssql://senzing:LLlAx23mb6utUQ8UBZ5h@sz-legal-antelope-mssql-server.database.windows.net:1433:G2"}}'

------------
--> {"SSN_NUMBER": "388-69-4882", "NAME_FIRST": "JOHNNIE", "PASSPORT_NUMBER": "CN5QGN8HY8", "GENDER": "M", "CC_ACCOUNT_NUMBER": "541119397002419249", "RECORD_ID": "526429955", "DSRC_ACTION": "A", "DRIVERS_LICENSE_NUMBER": "943105509", "DRIVERS_LICENSE_STATE": "IV", "PHONE_NUMBER": "355-9553", "NAME_LAST": "H", "ADDR_LINE1": "69 Cayuga CT", "DATA_SOURCE": "TEST"}
------------
DATA_SOURCE: TEST
RECORD_ID: 526429955
>>>>> calling addRecord
2024-04-12 18:39:00.195 [:124207928690496] NOTE: TRACE: G2_addRecord([TEST],[526429955],[{"SSN_NUMBER": "388-69-4882", "NAME_FIRST": "JOHNNIE", "PASSPORT_NUMBER": "CN5QGN8HY8", "GENDER": "M", "CC_ACCOUNT_NUMBER": "541119397002419249", "RECORD_ID": "526429955", "DSRC_ACTION": "A", "DRIVERS_LICENSE_NUMBER": "943105509", "DRIVERS_LICENSE_STATE": "IV", "PHONE_NUMBER": "355-9553", "NAME_LAST": "H", "ADDR_LINE1": "69 Cayuga CT", "DATA_SOURCE": "TEST"}],[])
2024-04-12 18:39:00.195 [:124207928690496] DBUG: Creating engine processor database connection.
2024-04-12 18:39:00.196 [:124207928690496] DBUG: Opening connection to database type mssql:
2024-04-12 18:39:00.215 [:124207928690496] DBUG: Connected to database.
2024-04-12 18:39:00.215 [:124207928690496] DBUG: Shards are not used for the data store.
2024-04-12 18:39:00.216 [:124207928690496] DBUG: Done creating engine processor database connection.
2024-04-12 18:39:00.217 [:124207928690496] DBUG: Testing (and possible reconnect) to database connection:
2024-04-12 18:39:00.236 [:124207928690496] DBUG: Database connection tested.
2024-04-12 18:39:00.283 [:124207928690496] DBUG: Found JSON input, mapping to UMF...
2024-04-12 18:39:00.284 [:124207928690496] DBUG: Populating cache for sequence [OBS_ID]
2024-04-12 18:39:00.311 [:124207928690496] DBUG: ENTERING KEYLESS PROCESSING
2024-04-12 18:39:00.315 [:124207928690496] DBUG: Parsing and Standardizing Features for OBS_ENT
Killed
```

#### inside Senzing container:

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
&& ACCEPT_EULA=Y apt-get -y install msodbcsql17 \
&& ACCEPT_EULA=Y apt-get -y install mssql-tools
echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc
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
isql $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 senzing $SENZING_DB_PWD

sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "SELECT name FROM sys.tables;"
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -i /tmp/q.sql -o /tmp/q.out
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "SELECT * FROM sys_vars"
sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -I  -Q "SELECT GETDATE(), COUNT(*) FROM DSRC_RECORD;"

sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -Q 'select min(FIRST_SEEN_DT) load_start, count(*) / (DATEDIFF(s,min(FIRST_SEEN_DT),max(FIRST_SEEN_DT))/60) erpm, count(*) total, DATEDIFF(mi,min(FIRST_SEEN_DT),max(FIRST_SEEN_DT))/(60.0*24.0) duration from DSRC_RECORD WITH (NOLOCK);'

```
docker run -it --rm public.ecr.aws/senzing/senzingapi-tools:staging
apt-get update
apt-get -y install senzingapi-setup
apt-get -y install senzingapi-setup=3.9.1-24074


docker run -it --rm public.ecr.aws/senzing/senzingapi-tools:staging

root@aed44e5b3fcb:/# apt policy senzingapi-tools
senzingapi-tools:
  Installed: 3.9.1-24074
  Candidate: 3.9.1-24074
  Version table:
 *** 3.9.1-24074 100
        100 /var/lib/dpkg/status

root@aed44e5b3fcb:/# apt install senzingapi-setup
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
E: Unable to locate package senzingapi-setup
root@aed44e5b3fcb:/# apt update
Get:1 http://deb.debian.org/debian bullseye InRelease [116 kB]
Get:2 http://deb.debian.org/debian-security bullseye-security InRelease [48.4 kB]
Get:3 http://deb.debian.org/debian bullseye-updates InRelease [44.1 kB]
Get:4 http://deb.debian.org/debian bullseye/main amd64 Packages [8068 kB]
Get:5 https://senzing-staging-apt.s3.amazonaws.com stable InRelease [2899 B]
Get:6 https://senzing-staging-apt.s3.amazonaws.com stable/main amd64 Packages [8200 B]
Get:7 http://deb.debian.org/debian-security bullseye-security/main amd64 Packages [271 kB]
Get:8 http://deb.debian.org/debian bullseye-updates/main amd64 Packages [18.8 kB]
Fetched 8576 kB in 6s (1544 kB/s)
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
9 packages can be upgraded. Run 'apt list --upgradable' to see them.
root@aed44e5b3fcb:/# apt policy senzingapi-tools
senzingapi-tools:
  Installed: 3.9.1-24074
  Candidate: 4.0.0-24017
  Version table:
     4.0.0-24017 500
        500 https://senzing-staging-apt.s3.amazonaws.com stable/main amd64 Packages
     3.9.1-24093 500
        500 https://senzing-staging-apt.s3.amazonaws.com stable/main amd64 Packages
     3.9.1-24092 500
        500 https://senzing-staging-apt.s3.amazonaws.com stable/main amd64 Packages
     3.9.1-24089 500
        500 https://senzing-staging-apt.s3.amazonaws.com stable/main amd64 Packages
     3.9.1-24088 500
        500 https://senzing-staging-apt.s3.amazonaws.com stable/main amd64 Packages
 *** 3.9.1-24074 500
        500 https://senzing-staging-apt.s3.amazonaws.com stable/main amd64 Packages
        100 /var/lib/dpkg/status
     3.9.0-24071 500
        500 https://senzing-staging-apt.s3.amazonaws.com stable/main amd64 Packages
     3.9.0-24068 500
        500 https://senzing-staging-apt.s3.amazonaws.com stable/main amd64 Packages
     3.9.0-24064 500
        500 https://senzing-staging-apt.s3.amazonaws.com stable/main amd64 Packages
     3.9.0-24058 500
        500 https://senzing-staging-apt.s3.amazonaws.com stable/main amd64 Packages
     3.9.0-24053 500
        500 https://senzing-staging-apt.s3.amazonaws.com stable/main amd64 Packages
     3.8.3-24043 500
        500 https://senzing-staging-apt.s3.amazonaws.com stable/main amd64 Packages
     3.8.3-24037 500
        500 https://senzing-staging-apt.s3.amazonaws.com stable/main amd64 Packages

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


### NOTES:

#### references:

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