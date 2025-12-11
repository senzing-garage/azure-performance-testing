// =============================================================================
// Senzing Entity Resolution Infrastructure - Parameter File
// =============================================================================
// Usage:
//   az deployment group create \
//     --resource-group senzing-rg \
//     --template-file main.bicep \
//     --parameters main.bicepparam \
//     --parameters senzingLicenseBase64='<your-base64-license>'
// =============================================================================

using './main.bicep'

// Required - MUST be overridden at deployment time via:
//   --parameters senzingLicenseBase64='<your-actual-license>'
param senzingLicenseBase64 = 'REPLACE_WITH_YOUR_LICENSE'

// Template variant: 'simple' or 'full'
param templateVariant = 'full'

// Location - defaults to resource group location
// param location = 'eastus2'

// Base name for resources
param baseName = 'senzing'

// Network configuration
// Three separate Container Apps subnets for independent vCPU quotas (~100 vCPU each)
param vnetAddressPrefix = '10.0.0.0/16'
param containerAppsCoreSubnetPrefix = '10.0.8.0/23'      // Core: init jobs, tools, redoer
param containerAppsLoaderSubnetPrefix = '10.0.10.0/23'   // Loader: streamloader (2 CPU × 35 = 70 vCPU)
param containerAppsProducerSubnetPrefix = '10.0.12.0/23' // Producer: producer jobs (2 CPU × 25 = 50 vCPU)
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
//
// AWS to Azure SQL SKU mapping:
//   db.r6i.8xlarge  (32 vCPU)  -> GP_Gen5_32 or BC_Gen5_32
//   db.r6i.24xlarge (96 vCPU)  -> BC_Gen5_80 (Azure max is 80 vCores)
//
// GP = General Purpose (remote storage, ~$1,200/month for 32 vCores)
// BC = Business Critical (local SSD, ~$3,200/month for 32 vCores)
// =============================================================================

// -----------------------------------------------------------------------------
// Configuration: 25M Records (Standard)
// Estimated time: ~2-3 hours
// -----------------------------------------------------------------------------
param sqlSku = 'BC_Gen5_32'  // Changed from GP_Gen5_32 for local SSD performance
param serviceBusSku = 'Premium'  // Premium = no throttling (~$22/day), Standard = throttled (~$10/month)
param streamLoaderMinReplicas = 8
param streamLoaderMaxReplicas = 20
param redoerMaxReplicas = 10
param runStreamProducer = false
param skipStreamLoader = false
param recordMax = 2000000  // 2M for baseline test

// -----------------------------------------------------------------------------
// Configuration: 25M Records (Fast) - Uncomment to use
// Estimated time: ~1-1.5 hours
// -----------------------------------------------------------------------------
// param sqlSku = 'BC_Gen5_32'
// param streamLoaderMaxReplicas = 40
// param redoerMaxReplicas = 5
// param runStreamProducer = false
// param recordMax = 25000000

// -----------------------------------------------------------------------------
// Configuration: 50M Records - Uncomment to use
// Estimated time: ~4-5 hours
// -----------------------------------------------------------------------------
// param sqlSku = 'GP_Gen5_32'
// param streamLoaderMaxReplicas = 35
// param redoerMaxReplicas = 5
// param runStreamProducer = false
// param recordMax = 50000000

// -----------------------------------------------------------------------------
// Configuration: 100M Records - Uncomment to use
// Estimated time: ~8-10 hours
// Note: 50 loaders × 2 CPU = 100 vCPU (at quota limit)
// For more loaders, request quota increase or reduce CPU per loader
// -----------------------------------------------------------------------------
// param sqlSku = 'BC_Gen5_80'
// param streamLoaderMaxReplicas = 50
// param redoerMaxReplicas = 10
// param runStreamProducer = false
// param recordMax = 100000000

// =============================================================================
// Test Data Loading Options
// =============================================================================
// Test data file URL - Azure Blob is faster than S3
param testDataInputUrl = 'https://ronperftestdata.blob.core.windows.net/testdatasets/test-dataset-100m.json.gz'

// Azure Container Registry for image pulls
param acrName = 'RonACRPerfTesting'
param acrResourceGroup = 'ron-acr-perf-testing'

// Container images - using Azure Container Registry
// ACR name: RonACRPerfTesting -> ronacrperftesting.azurecr.io
param initDatabaseImage = 'docker.io/senzing/init-database:latest'
param senzingToolsImage = 'ronacrperftesting.azurecr.io/senzingsdk-tools-mssql:staging'
param streamLoaderImage = 'ronacrperftesting.azurecr.io/sz_sb_consumer:staging'
param redoerImage = 'ronacrperftesting.azurecr.io/redoer:staging'
param streamProducerImage = 'ronacrperftesting.azurecr.io/stream-producer:1.8.7'
