// =============================================================================
// Senzing Entity Resolution Infrastructure - Azure Bicep Template
// =============================================================================
// Migrated from AWS CloudFormation templates:
// - CFT-ECS-Aurora.yaml (simple)
// - cloudformationAuroraProvisionedSingleDB-IAM.yaml (full)
//
// This template deploys:
// - VNet with subnets for Container Apps and Azure SQL
// - Azure SQL Database with Managed Identity auth
// - Azure Container Apps for Senzing services
// - Azure Service Bus for messaging (full template only)
// - Key Vault for secrets
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

@description('Azure Container Registry name (for image pull permissions)')
param acrName string = ''

@description('Resource group containing the ACR (if different from deployment resource group)')
param acrResourceGroup string = ''

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
// Variables
// =============================================================================

var uniqueSuffix = uniqueString(resourceGroup().id)
var resourcePrefix = '${baseName}-${uniqueSuffix}'
var runFullServices = templateVariant == 'full'
var acrLoginServer = !empty(acrName) ? toLower('${acrName}.azurecr.io') : ''

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

// Senzing Engine Configuration JSON - Managed Identity based (for runtime)
var senzingConfigManagedIdentity = {
  PIPELINE: {
    CONFIGPATH: '/etc/opt/senzing'
    LICENSESTRINGBASE64: senzingLicenseBase64
    RESOURCEPATH: '/opt/senzing/er/resources'
    SUPPORTPATH: '/opt/senzing/data'
  }
  SQL: {
    BACKEND: 'SQL'
    // Connection string uses Managed Identity (ActiveDirectoryMsi) for Azure SQL authentication
    // Format: mssql://client-id:dummy@server:port:database/?authentication=ActiveDirectoryMsi&encrypt=yes
    CONNECTION: 'mssql://${managedIdentity.outputs.clientId}:dummy@${sqlServer.outputs.fqdn}:1433:${databaseName}/?authentication=ActiveDirectoryMsi&encrypt=yes'
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
// Modules - Security
// =============================================================================

// Managed Identity for runtime services
module managedIdentity 'modules/database/managed-identity.bicep' = {
  name: 'managedIdentity'
  params: {
    name: '${resourcePrefix}-mi'
    location: location
  }
}

// Key Vault
module keyVault 'modules/security/keyvault.bicep' = {
  name: 'keyVault'
  params: {
    name: replace('${resourcePrefix}-kv', '-', '')
    location: location
    managedIdentityPrincipalId: managedIdentity.outputs.principalId
    senzingLicenseBase64: senzingLicenseBase64
    sqlPassword: sqlAdminPassword
    senzingConfigPassword: string(senzingConfigPassword)
    senzingConfigManagedIdentity: string(senzingConfigManagedIdentity)
  }
}

// ACR Pull Role Assignment (if using private ACR)
// Uses subscription-level deployment to handle cross-resource-group ACR
var effectiveAcrResourceGroup = !empty(acrResourceGroup) ? acrResourceGroup : resourceGroup().name
module acrPullRole 'modules/containers/acr-pull-role.bicep' = if (!empty(acrName)) {
  name: 'acrPullRole'
  scope: resourceGroup(effectiveAcrResourceGroup)
  params: {
    acrName: acrName
    principalId: managedIdentity.outputs.principalId
  }
}

// =============================================================================
// Modules - Database
// =============================================================================

// Azure SQL Server and Database
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
    managedIdentityPrincipalId: managedIdentity.outputs.principalId
    managedIdentityName: managedIdentity.outputs.name
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
    managedIdentityPrincipalId: managedIdentity.outputs.principalId
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

// Init Database Job - Uses PASSWORD authentication
module initDatabaseJob 'modules/containers/init-database-job.bicep' = {
  name: 'initDatabaseJob'
  params: {
    name: '${resourcePrefix}-init-db'
    location: location
    containerAppsEnvId: containerAppsEnvCore.outputs.id
    image: initDatabaseImage
    senzingConfigJson: string(senzingConfigPassword)
  }
  dependsOn: [
    acrPullRole  // Wait for ACR pull permission before pulling images
  ]
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

// Create Managed Identity User Job - Uses PASSWORD to create MI user
module createMiUserJob 'modules/containers/create-mi-user-job.bicep' = {
  name: 'createMiUserJob'
  params: {
    name: '${resourcePrefix}-create-mi'
    location: location
    containerAppsEnvId: containerAppsEnvCore.outputs.id
    sqlHost: sqlServer.outputs.fqdn
    sqlPort: 1433
    sqlDatabase: databaseName
    sqlAdminUser: sqlAdminLogin
    sqlAdminPassword: sqlAdminPassword
    managedIdentityName: managedIdentity.outputs.name
  }
  dependsOn: [
    configureDatabaseJob
  ]
}

// G2ConfigTool Job - Uses Managed Identity authentication
module g2ConfigToolJob 'modules/containers/g2configtool-job.bicep' = {
  name: 'g2ConfigToolJob'
  params: {
    name: '${resourcePrefix}-g2config'
    location: location
    containerAppsEnvId: containerAppsEnvCore.outputs.id
    image: senzingToolsImage  // Use tools image which has MSSQL drivers
    senzingConfigJson: string(senzingConfigManagedIdentity)
    managedIdentityId: managedIdentity.outputs.id
    acrLoginServer: acrLoginServer
  }
  dependsOn: [
    createMiUserJob
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
    senzingConfigJson: string(senzingConfigManagedIdentity)
    managedIdentityId: managedIdentity.outputs.id
    acrLoginServer: acrLoginServer
  }
  dependsOn: [
    g2ConfigToolJob
  ]
}

// StreamLoader App - Full template only, runs in dedicated Loader environment
// When skipStreamLoader is true, StreamLoader is not deployed initially.
// Deploy it later with: az deployment group create ... --parameters skipStreamLoader=false
module streamLoaderApp 'modules/containers/streamloader-app.bicep' = if (runFullServices && !skipStreamLoader) {
  name: 'streamLoaderApp'
  params: {
    name: '${resourcePrefix}-loader'
    location: location
    containerAppsEnvId: containerAppsEnvLoader!.outputs.id
    image: streamLoaderImage
    senzingConfigJson: string(senzingConfigManagedIdentity)
    managedIdentityId: managedIdentity.outputs.id
    serviceBusNamespace: serviceBus!.outputs.namespaceName
    serviceBusQueueName: 'senzing-input'
    serviceBusConnectionString: serviceBus!.outputs.listenConnectionString
    serviceBusManageConnectionString: serviceBus!.outputs.manageConnectionString
    minReplicas: streamLoaderMinReplicas
    maxReplicas: streamLoaderMaxReplicas
    acrLoginServer: acrLoginServer
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
    senzingConfigJson: string(senzingConfigManagedIdentity)
    managedIdentityId: managedIdentity.outputs.id
    maxReplicas: redoerMaxReplicas
    acrLoginServer: acrLoginServer
  }
  dependsOn: [
    g2ConfigToolJob
  ]
}

// =============================================================================
// Modules - Test Data Loading (Optional)
// =============================================================================

// Stream Producer Jobs - Multiple parallel jobs to load test records into Service Bus queue
// Each job handles a slice of records, runs in dedicated Producer environment
module streamProducerJobs 'modules/containers/stream-producer-jobs.bicep' = if (runFullServices && runStreamProducer) {
  name: 'streamProducerJobs'
  params: {
    name: '${resourcePrefix}-prod'
    location: location
    containerAppsEnvId: containerAppsEnvProducer!.outputs.id
    image: streamProducerImage
    managedIdentityId: managedIdentity.outputs.id
    serviceBusConnectionString: serviceBus!.outputs.connectionString
    serviceBusQueueName: 'senzing-input'
    recordMax: recordMax
    acrLoginServer: acrLoginServer
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
output keyVaultUri string = keyVault.outputs.vaultUri
output managedIdentityClientId string = managedIdentity.outputs.clientId

output serviceBusNamespace string = runFullServices ? serviceBus!.outputs.namespaceName : ''
output streamLoaderAppFqdn string = (runFullServices && !skipStreamLoader) ? streamLoaderApp!.outputs.fqdn : ''
output redoerAppFqdn string = runFullServices ? redoerApp!.outputs.fqdn : ''
output streamProducerJobCount int = (runFullServices && runStreamProducer) ? streamProducerJobs!.outputs.jobCount : 0
output streamProducerJobNames array = (runFullServices && runStreamProducer) ? streamProducerJobs!.outputs.jobNames : []
