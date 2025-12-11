// =============================================================================
// Senzing Entity Resolution Infrastructure - Parameter File
// =============================================================================
// Entra ID Password Authentication Version (No Managed Identity)
//
// Usage:
//   az deployment group create \
//     --resource-group senzing-rg \
//     --template-file main.bicep \
//     --parameters main.bicepparam \
//     --parameters senzingLicenseBase64='<your-base64-license>' \
//     --parameters entraUserEmail='senzing@yourdomain.com' \
//     --parameters entraUserPassword=$ENTRA_PASSWORD \
//     --parameters acrUsername='senzing-pull-token' \
//     --parameters acrPassword=$ACR_TOKEN_PASSWORD
// =============================================================================

using './main.bicep'

// Required - MUST be overridden at deployment time via:
//   --parameters senzingLicenseBase64='<your-actual-license>'
param senzingLicenseBase64 = 'REPLACE_WITH_YOUR_LICENSE'

// =============================================================================
// Entra ID Password Authentication
// =============================================================================
// These MUST be overridden at deployment time
// The Entra ID user must exist in Azure AD before deployment

param entraUserEmail = 'senzing@yourdomain.com'  // Override at deployment
param entraUserPassword = 'REPLACE_THIS' // Override at deployment

// Get Object ID with: az ad user show --id "user@domain.com" --query id -o tsv
param entraUserObjectId = 'REPLACE_WITH_OBJECT_ID'  // Override at deployment

// =============================================================================
// ACR Repository Token Authentication
// =============================================================================
// Create token before deployment:
//   az acr scope-map create --name senzing-pull-scope --registry RonACRPerfTesting \
//     --repository senzingsdk-tools-mssql content/read \
//     --repository sz_sb_consumer content/read \
//     --repository redoer content/read \
//     --repository stream-producer content/read
//   az acr token create --name senzing-pull-token --registry RonACRPerfTesting \
//     --scope-map senzing-pull-scope
//   az acr token credential generate --name senzing-pull-token --registry RonACRPerfTesting --password1

param acrLoginServer = 'ronacrperftesting.azurecr.io'
param acrUsername = 'senzing-pull-token'  // Override with your token name
// acrPassword - pass via command line: --parameters acrPassword=$ACR_TOKEN_PASSWORD

// =============================================================================
// Template Configuration
// =============================================================================

// Template variant: 'simple' or 'full'
param templateVariant = 'full'

// Location - defaults to resource group location
// param location = 'eastus2'

// Base name for resources
param baseName = 'senzing'

// Network configuration
param vnetAddressPrefix = '10.0.0.0/16'
param containerAppsCoreSubnetPrefix = '10.0.8.0/23'      // Core: init jobs, tools, redoer
param containerAppsLoaderSubnetPrefix = '10.0.10.0/23'   // Loader: streamloader
param containerAppsProducerSubnetPrefix = '10.0.12.0/23' // Producer: producer jobs
param sqlSubnetPrefix = '10.0.16.0/22'

// Database configuration
param sqlAdminLogin = 'senzing'
param databaseName = 'SZ'
param sqlMaxSizeGB = 256

// =============================================================================
// Performance Test Configurations
// =============================================================================
// Choose ONE configuration below by uncommenting it and commenting the others.
// Each configuration is tuned for a specific record count.
// =============================================================================

// -----------------------------------------------------------------------------
// Configuration: 2M Records (Baseline Test)
// -----------------------------------------------------------------------------
param sqlSku = 'BC_Gen5_32'
param serviceBusSku = 'Premium'
param streamLoaderMinReplicas = 8
param streamLoaderMaxReplicas = 30
param redoerMaxReplicas = 10
param runStreamProducer = false
param skipStreamLoader = false
param recordMax = 2000000

// -----------------------------------------------------------------------------
// Configuration: 25M Records - Uncomment to use
// -----------------------------------------------------------------------------
// param sqlSku = 'BC_Gen5_32'
// param serviceBusSku = 'Premium'
// param streamLoaderMinReplicas = 8
// param streamLoaderMaxReplicas = 40
// param redoerMaxReplicas = 10
// param runStreamProducer = false
// param skipStreamLoader = false
// param recordMax = 25000000

// =============================================================================
// Container Images (from Azure Container Registry)
// =============================================================================

param initDatabaseImage = 'docker.io/senzing/init-database:latest'
param senzingToolsImage = 'ronacrperftesting.azurecr.io/senzingsdk-tools-mssql:staging'
param streamLoaderImage = 'ronacrperftesting.azurecr.io/sz_sb_consumer:staging'
param redoerImage = 'ronacrperftesting.azurecr.io/redoer:staging'
param streamProducerImage = 'ronacrperftesting.azurecr.io/stream-producer:1.8.7'

// Test data file URL
param testDataInputUrl = 'https://ronperftestdata.blob.core.windows.net/testdatasets/test-dataset-100m.json.gz'
