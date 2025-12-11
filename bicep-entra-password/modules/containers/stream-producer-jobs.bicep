// =============================================================================
// Stream Producer Jobs Module (Parallel)
// =============================================================================
// Creates multiple Container Apps Jobs that load test records into Service Bus
// Each job handles a slice of the data file (10M records per job stride)
// This parallelizes data loading for faster performance testing setup
// Uses ACR token authentication (no Managed Identity)
// =============================================================================

@description('Base name for the jobs')
param name string

@description('Location for the jobs')
param location string

@description('Container Apps Environment ID')
param containerAppsEnvId string

@description('Stream Producer container image')
param image string

@description('Service Bus connection string (stream-producer does not support MI)')
@secure()
param serviceBusConnectionString string

@description('Service Bus queue name')
param serviceBusQueueName string

@description('Maximum number of records to load')
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
param recordMax int

@description('ACR login server (e.g., myacr.azurecr.io)')
param acrLoginServer string = ''

@description('ACR username (token name or admin username)')
param acrUsername string = ''

@description('ACR password (token password or admin password)')
@secure()
param acrPassword string = ''

@description('Input data file URL')
param inputUrl string

// =============================================================================
// Variables
// =============================================================================

// Stride for parallel producer jobs
// With Premium Service Bus: smaller stride = more parallelism = faster queue fill
// With Standard Service Bus: use larger strides to avoid throttling
// Current: Optimized for Premium tier (~20-25 parallel jobs)
var stride = recordMax <= 5000000 ? 500000      // ≤5M: 500K stride (up to 10 jobs)
           : recordMax <= 10000000 ? 500000     // ≤10M: 500K stride (20 jobs)
           : recordMax <= 25000000 ? 1000000    // ≤25M: 1M stride (25 jobs)
           : recordMax <= 50000000 ? 2000000    // ≤50M: 2M stride (25 jobs)
           : 4000000                             // 100M: 4M stride (25 jobs)

// Calculate number of jobs needed
// For recordMax <= stride, we need 1 job
// For recordMax > stride, we need ceil(recordMax / stride) jobs
var jobCount = recordMax <= stride ? 1 : ((recordMax + stride - 1) / stride)

// Generate job configurations with min/max ranges
// Job 0: 0 to min(stride, recordMax)
// Job 1: stride+1 to min(2*stride, recordMax)
// etc.
var jobConfigs = [for i in range(0, jobCount): {
  index: i
  recordMin: i * stride
  recordMax: min((i + 1) * stride, recordMax)
}]

// =============================================================================
// Container Apps Jobs - Stream Producers (Parallel)
// =============================================================================

resource streamProducerJobs 'Microsoft.App/jobs@2023-05-01' = [for (config, i) in jobConfigs: {
  name: '${name}-${i}'
  location: location
  properties: {
    environmentId: containerAppsEnvId
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 86400 // 24 hours (large data loads take time)
      replicaRetryLimit: 0
      secrets: concat([
        {
          name: 'servicebus-connection'
          value: serviceBusConnectionString
        }
      ], (!empty(acrLoginServer) && !empty(acrPassword)) ? [
        {
          name: 'acr-password'
          value: acrPassword
        }
      ] : [])
      registries: (!empty(acrLoginServer) && !empty(acrUsername)) ? [
        {
          server: acrLoginServer
          username: acrUsername
          passwordSecretRef: 'acr-password'
        }
      ] : []
    }
    template: {
      containers: [
        {
          name: 'stream-producer'
          image: image
          resources: {
            cpu: json('2.0')
            memory: '4Gi'
          }
          env: [
            {
              name: 'SENZING_SUBCOMMAND'
              value: 'gzipped-json-to-azure-queue'
            }
            {
              name: 'SENZING_INPUT_URL'
              value: inputUrl
            }
            {
              name: 'SENZING_DEFAULT_DATA_SOURCE'
              value: 'TEST'
            }
            {
              name: 'SENZING_DEFAULT_ENTITY_TYPE'
              value: 'GENERIC'
            }
            {
              name: 'SENZING_RECORD_MIN'
              value: string(config.recordMin)
            }
            {
              name: 'SENZING_RECORD_MAX'
              value: string(config.recordMax)
            }
            {
              name: 'SENZING_RECORD_MONITOR'
              value: '100000'
            }
            {
              name: 'SENZING_RECORDS_PER_MESSAGE'
              value: '1'
            }
            {
              name: 'SENZING_MONITORING_PERIOD_IN_SECONDS'
              value: '60'
            }
            {
              name: 'SENZING_READ_QUEUE_MAXSIZE'
              value: '500'
            }
            {
              name: 'SENZING_THREADS_PER_PRINT'
              value: '30'
            }
            {
              name: 'SENZING_AZURE_QUEUE_CONNECTION_STRING'
              secretRef: 'servicebus-connection'
            }
            {
              name: 'SENZING_AZURE_QUEUE_NAME'
              value: serviceBusQueueName
            }
          ]
        }
      ]
    }
  }
}]

// =============================================================================
// Outputs
// =============================================================================

output jobCount int = jobCount
output jobNames array = [for i in range(0, jobCount): '${name}-${i}']
output jobConfigs array = jobConfigs
