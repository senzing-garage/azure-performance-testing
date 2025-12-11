// =============================================================================
// Senzing Entity Resolution Infrastructure - Azure Bicep Template
// =============================================================================
// Entra ID Password Authentication Version (No Managed Identity)
//
// This template deploys:
// - VNet with subnets for Container Apps and Azure SQL
// - Azure SQL Database with Entra ID Password auth
// - Azure Container Apps for Senzing services
// - Azure Service Bus for messaging (full template only)
// =============================================================================

targetScope = 'resourceGroup'

// =============================================================================
// Parameters
// =============================================================================

@description('Base64-encoded Senzing license string')
@secure()
param senzingLicenseBase64 string

@description('Location for all resources')
param location string = resourceGroup().location

@description('Base name for all resources')
@minLength(3)
@maxLength(20)
param baseName string = 'senzing'

@description('Template variant: simple (SSHD only) or full (all services)')
@allowed([
  'simple'
  'full'
])
param templateVariant string = 'full'

@description('VNet address space')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Core Container Apps subnet CIDR (init jobs, tools, redoer)')
param containerAppsCoreSubnetPrefix string = '10.0.8.0/23'

@description('Loader Container Apps subnet CIDR (streamloader)')
param containerAppsLoaderSubnetPrefix string = '10.0.10.0/23'

@description('Producer Container Apps subnet CIDR (producer jobs)')
param containerAppsProducerSubnetPrefix string = '10.0.12.0/23'

@description('Azure SQL subnet CIDR')
param sqlSubnetPrefix string = '10.0.16.0/22'

@description('Azure SQL administrator login')
param sqlAdminLogin string = 'senzing'

@description('Azure SQL administrator password (used only for init)')
@secure()
param sqlAdminPassword string = newGuid()

@description('Azure SQL SKU name (DTU or vCore based)')
param sqlSku string = 'GP_Gen5_8'

@description('Azure SQL max size in GB')
param sqlMaxSizeGB int = 256

@description('Database name')
param databaseName string = 'SZ'

@description('StreamLoader max replicas')
param streamLoaderMaxReplicas int = 50

@description('Redoer max replicas')
param redoerMaxReplicas int = 5

@description('Service Bus SKU: Standard (~$10/month, throttled) or Premium (~$677/month, no throttling)')
@allowed([
  'Standard'
  'Premium'
])
param serviceBusSku string = 'Premium'

@description('Senzing init-database image')
param initDatabaseImage string = 'public.ecr.aws/senzing/init-database:latest'

@description('Senzing tools image (for tools container and g2configtool job)')
param senzingToolsImage string = 'public.ecr.aws/senzing/senzingsdk-tools:latest'

@description('Senzing StreamLoader image')
param streamLoaderImage string = 'public.ecr.aws/senzing/stream-loader:latest'

@description('Senzing Redoer image')
param redoerImage string = 'public.ecr.aws/senzing/redoer:latest'

@description('Senzing Stream Producer image')
param streamProducerImage string = 'public.ecr.aws/senzing/stream-producer:latest'

@description('Run Stream Producer to load test data')
param runStreamProducer bool = false

@description('Skip StreamLoader deployment (deploy it later when ready to start perf test)')
param skipStreamLoader bool = false

@description('Minimum StreamLoader replicas (set to match AWS for comparison)')
param streamLoaderMinReplicas int = 8

@description('Number of test records to load (only used if runStreamProducer is true)')
@allowed([
  1
  1000000      // 1M
  2000000      // 2M
  5000000      // 5M
  10000000     // 10M
  20000000     // 20M
  25000000     // 25M
  50000000     // 50M
  100000000    // 100M
])
param recordMax int = 1000000

@description('Test data file URL (use Azure Blob for best performance)')
param testDataInputUrl string = 'https://ronperftestdata.blob.core.windows.net/testdatasets/test-dataset-100m.json.gz'

// =============================================================================
// Entra ID Password Authentication Parameters
// =============================================================================

@description('Entra ID user email for SQL authentication')
param entraUserEmail string

@description('Entra ID user password for SQL authentication')
@secure()
param entraUserPassword string

@description('Entra ID user Object ID (run: az ad user show --id "user@domain.com" --query id -o tsv)')
param entraUserObjectId string

// =============================================================================
// ACR Authentication Parameters (Token-based, no MI)
// =============================================================================

@description('ACR login server (e.g., myacr.azurecr.io)')
param acrLoginServer string = ''

@description('ACR username (token name or admin username)')
param acrUsername string = ''

@description('ACR password (token password or admin password)')
@secure()
param acrPassword string = ''

// =============================================================================
// Variables
// =============================================================================

var uniqueSuffix = uniqueString(resourceGroup().id)
var resourcePrefix = '${baseName}-${uniqueSuffix}'
var runFullServices = templateVariant == 'full'

// Senzing Engine Configuration JSON - Password based (for init-database)
var senzingConfigPassword = {
  PIPELINE: {
    CONFIGPATH: '/etc/opt/senzing'
    LICENSESTRINGBASE64: senzingLicenseBase64
    RESOURCEPATH: '/opt/senzing/er/resources'
    SUPPORTPATH: '/opt/senzing/data'
  }
  SQL: {
    BACKEND: 'SQL'
    // Format: mssql://user:password@server:port:database/?encrypt=yes
    CONNECTION: 'mssql://${sqlAdminLogin}:${sqlAdminPassword}@${sqlServer.outputs.fqdn}:1433:${databaseName}/?encrypt=yes'
  }
}

// Senzing Engine Configuration JSON - Entra ID Password based (for runtime)
var senzingConfigEntraPassword = {
  PIPELINE: {
    CONFIGPATH: '/etc/opt/senzing'
    LICENSESTRINGBASE64: senzingLicenseBase64
    RESOURCEPATH: '/opt/senzing/er/resources'
    SUPPORTPATH: '/opt/senzing/data'
  }
  SQL: {
    BACKEND: 'SQL'
    // Connection string uses Entra ID Password authentication
    // uriComponent() URL-encodes special characters like @ in email and special chars in password
    // Format: mssql://user@domain.com:password@server:port:database/?authentication=ActiveDirectoryPassword&encrypt=yes
    CONNECTION: 'mssql://${uriComponent(entraUserEmail)}:${uriComponent(entraUserPassword)}@${sqlServer.outputs.fqdn}:1433:${databaseName}/?authentication=ActiveDirectoryPassword&encrypt=yes'
  }
}

// =============================================================================
// Modules - Core Infrastructure
// =============================================================================

// Log Analytics Workspace
module logAnalytics 'modules/monitoring/log-analytics.bicep' = {
  name: 'logAnalytics'
  params: {
    name: '${resourcePrefix}-logs'
    location: location
  }
}

// Virtual Network
module network 'modules/network/vnet.bicep' = {
  name: 'network'
  params: {
    name: '${resourcePrefix}-vnet'
    location: location
    addressPrefix: vnetAddressPrefix
    containerAppsCoreSubnetPrefix: containerAppsCoreSubnetPrefix
    containerAppsLoaderSubnetPrefix: containerAppsLoaderSubnetPrefix
    containerAppsProducerSubnetPrefix: containerAppsProducerSubnetPrefix
    sqlSubnetPrefix: sqlSubnetPrefix
  }
}

// Network Security Groups
module nsg 'modules/network/nsg.bicep' = {
  name: 'nsg'
  params: {
    name: '${resourcePrefix}-nsg'
    location: location
  }
}

// =============================================================================
// Modules - Database
// =============================================================================

// Azure SQL Server and Database (with Entra user as AAD admin)
module sqlServer 'modules/database/sql-database.bicep' = {
  name: 'sqlServer'
  params: {
    name: '${resourcePrefix}-sql'
    location: location
    administratorLogin: sqlAdminLogin
    administratorPassword: sqlAdminPassword
    skuName: sqlSku
    maxSizeGB: sqlMaxSizeGB
    databaseName: databaseName
    subnetId: network.outputs.sqlSubnetId
    privateDnsZoneId: network.outputs.privateDnsZoneId
    entraUserEmail: entraUserEmail
    entraUserObjectId: entraUserObjectId
  }
}

// =============================================================================
// Modules - Messaging (Full template only)
// =============================================================================

module serviceBus 'modules/messaging/servicebus.bicep' = if (runFullServices) {
  name: 'serviceBus'
  params: {
    name: '${resourcePrefix}-bus'
    location: location
    sku: serviceBusSku
  }
}

// =============================================================================
// Modules - Container Apps Environments
// =============================================================================
// Three separate environments for independent vCPU quotas (~100 vCPU each):
// - Core: Init jobs, Tools, Redoer
// - Loader: StreamLoader (high scaling with 2 CPU per replica)
// - Producer: Producer jobs (parallel data loading)
// =============================================================================

// Core Environment - Init jobs, Tools, Redoer
module containerAppsEnvCore 'modules/containers/container-apps-env.bicep' = {
  name: 'containerAppsEnvCore'
  params: {
    name: '${resourcePrefix}-cae-core'
    location: location
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    subnetId: network.outputs.containerAppsCoreSubnetId
  }
}

// Loader Environment - StreamLoader with high scaling
module containerAppsEnvLoader 'modules/containers/container-apps-env.bicep' = if (runFullServices) {
  name: 'containerAppsEnvLoader'
  params: {
    name: '${resourcePrefix}-cae-loader'
    location: location
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    subnetId: network.outputs.containerAppsLoaderSubnetId
  }
}

// Producer Environment - Producer jobs for data loading
module containerAppsEnvProducer 'modules/containers/container-apps-env.bicep' = if (runFullServices && runStreamProducer) {
  name: 'containerAppsEnvProducer'
  params: {
    name: '${resourcePrefix}-cae-producer'
    location: location
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    subnetId: network.outputs.containerAppsProducerSubnetId
  }
}

// =============================================================================
// Modules - Initialization Jobs
// =============================================================================

// Init Database Job - Uses SQL PASSWORD authentication
module initDatabaseJob 'modules/containers/init-database-job.bicep' = {
  name: 'initDatabaseJob'
  params: {
    name: '${resourcePrefix}-init-db'
    location: location
    containerAppsEnvId: containerAppsEnvCore.outputs.id
    image: initDatabaseImage
    senzingConfigJson: string(senzingConfigPassword)
  }
}

// Configure Database Job - Sets performance options (DELAYED_DURABILITY, etc.)
module configureDatabaseJob 'modules/containers/configure-database-job.bicep' = {
  name: 'configureDatabaseJob'
  params: {
    name: '${resourcePrefix}-config-db'
    location: location
    containerAppsEnvId: containerAppsEnvCore.outputs.id
    sqlHost: sqlServer.outputs.fqdn
    sqlPort: 1433
    sqlDatabase: databaseName
    sqlAdminUser: sqlAdminLogin
    sqlAdminPassword: sqlAdminPassword
  }
  dependsOn: [
    initDatabaseJob
  ]
}

// Create Entra ID User Job - Uses SQL PASSWORD to create Entra user
module createEntraUserJob 'modules/containers/create-entra-user-job.bicep' = {
  name: 'createEntraUserJob'
  params: {
    name: '${resourcePrefix}-entra'
    location: location
    containerAppsEnvId: containerAppsEnvCore.outputs.id
    sqlHost: sqlServer.outputs.fqdn
    sqlPort: 1433
    sqlDatabase: databaseName
    sqlAdminUser: sqlAdminLogin
    sqlAdminPassword: sqlAdminPassword
    entraUserEmail: entraUserEmail
  }
  dependsOn: [
    configureDatabaseJob
  ]
}

// G2ConfigTool Job - Uses Entra ID Password authentication
module g2ConfigToolJob 'modules/containers/g2configtool-job.bicep' = {
  name: 'g2ConfigToolJob'
  params: {
    name: '${resourcePrefix}-g2config'
    location: location
    containerAppsEnvId: containerAppsEnvCore.outputs.id
    image: senzingToolsImage
    senzingConfigJson: string(senzingConfigEntraPassword)
    acrLoginServer: acrLoginServer
    acrUsername: acrUsername
    acrPassword: acrPassword
  }
  dependsOn: [
    createEntraUserJob
  ]
}

// =============================================================================
// Modules - Runtime Services
// =============================================================================

// Tools App - Always deployed (access via `az containerapp exec`)
module toolsApp 'modules/containers/tools-app.bicep' = {
  name: 'toolsApp'
  params: {
    name: '${resourcePrefix}-tools'
    location: location
    containerAppsEnvId: containerAppsEnvCore.outputs.id
    image: senzingToolsImage
    senzingConfigJson: string(senzingConfigEntraPassword)
    acrLoginServer: acrLoginServer
    acrUsername: acrUsername
    acrPassword: acrPassword
  }
  dependsOn: [
    g2ConfigToolJob
  ]
}

// StreamLoader App - Full template only, runs in dedicated Loader environment
module streamLoaderApp 'modules/containers/streamloader-app.bicep' = if (runFullServices && !skipStreamLoader) {
  name: 'streamLoaderApp'
  params: {
    name: '${resourcePrefix}-loader'
    location: location
    containerAppsEnvId: containerAppsEnvLoader!.outputs.id
    image: streamLoaderImage
    senzingConfigJson: string(senzingConfigEntraPassword)
    serviceBusNamespace: serviceBus!.outputs.namespaceName
    serviceBusQueueName: 'senzing-input'
    serviceBusConnectionString: serviceBus!.outputs.listenConnectionString
    serviceBusManageConnectionString: serviceBus!.outputs.manageConnectionString
    minReplicas: streamLoaderMinReplicas
    maxReplicas: streamLoaderMaxReplicas
    acrLoginServer: acrLoginServer
    acrUsername: acrUsername
    acrPassword: acrPassword
  }
  dependsOn: [
    g2ConfigToolJob
  ]
}

// Redoer App - Full template only, runs in Core environment
module redoerApp 'modules/containers/redoer-app.bicep' = if (runFullServices) {
  name: 'redoerApp'
  params: {
    name: '${resourcePrefix}-redoer'
    location: location
    containerAppsEnvId: containerAppsEnvCore.outputs.id
    image: redoerImage
    senzingConfigJson: string(senzingConfigEntraPassword)
    maxReplicas: redoerMaxReplicas
    acrLoginServer: acrLoginServer
    acrUsername: acrUsername
    acrPassword: acrPassword
  }
  dependsOn: [
    g2ConfigToolJob
  ]
}

// =============================================================================
// Modules - Test Data Loading (Optional)
// =============================================================================

// Stream Producer Jobs - Multiple parallel jobs to load test records into Service Bus queue
module streamProducerJobs 'modules/containers/stream-producer-jobs.bicep' = if (runFullServices && runStreamProducer) {
  name: 'streamProducerJobs'
  params: {
    name: '${resourcePrefix}-prod'
    location: location
    containerAppsEnvId: containerAppsEnvProducer!.outputs.id
    image: streamProducerImage
    serviceBusConnectionString: serviceBus!.outputs.connectionString
    serviceBusQueueName: 'senzing-input'
    recordMax: recordMax
    acrLoginServer: acrLoginServer
    acrUsername: acrUsername
    acrPassword: acrPassword
    inputUrl: testDataInputUrl
  }
  dependsOn: [
    g2ConfigToolJob
  ]
}

// =============================================================================
// Outputs
// =============================================================================

output sqlServerFqdn string = sqlServer.outputs.fqdn
output containerAppsEnvCoreId string = containerAppsEnvCore.outputs.id
output containerAppsEnvLoaderId string = runFullServices ? containerAppsEnvLoader!.outputs.id : ''
output containerAppsEnvProducerId string = (runFullServices && runStreamProducer) ? containerAppsEnvProducer!.outputs.id : ''
output toolsAppName string = toolsApp.outputs.appName

output serviceBusNamespace string = runFullServices ? serviceBus!.outputs.namespaceName : ''
output streamLoaderAppFqdn string = (runFullServices && !skipStreamLoader) ? streamLoaderApp!.outputs.fqdn : ''
output redoerAppFqdn string = runFullServices ? redoerApp!.outputs.fqdn : ''
output streamProducerJobCount int = (runFullServices && runStreamProducer) ? streamProducerJobs!.outputs.jobCount : 0
output streamProducerJobNames array = (runFullServices && runStreamProducer) ? streamProducerJobs!.outputs.jobNames : []
