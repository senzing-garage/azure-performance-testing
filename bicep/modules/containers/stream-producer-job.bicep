// =============================================================================
// Stream Producer Job Module
// =============================================================================
// Creates Container Apps Job that loads test records into the Service Bus queue
// This is used for testing and performance benchmarking
// =============================================================================

@description('Name of the job')
param name string

@description('Location for the job')
param location string

@description('Container Apps Environment ID')
param containerAppsEnvId string

@description('Stream Producer container image')
param image string

@description('User-assigned Managed Identity resource ID')
param managedIdentityId string

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

@description('ACR login server (e.g., myacr.azurecr.io) - if provided, configures ACR pull with managed identity')
param acrLoginServer string = ''

// =============================================================================
// Container Apps Job - Stream Producer
// =============================================================================

resource streamProducerJob 'Microsoft.App/jobs@2023-05-01' = {
  name: name
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    environmentId: containerAppsEnvId
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 86400 // 24 hours (large data loads take time)
      replicaRetryLimit: 0
      registries: !empty(acrLoginServer) ? [
        {
          server: acrLoginServer
          identity: managedIdentityId
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
              value: 'https://public-read-access.s3.amazonaws.com/TestDataSets/test-dataset-100m.json.gz'
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
              value: '0'
            }
            {
              name: 'SENZING_RECORD_MAX'
              value: string(recordMax)
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
              value: '200'
            }
            {
              name: 'SENZING_THREADS_PER_PRINT'
              value: '30'
            }
            {
              name: 'SENZING_AZURE_QUEUE_CONNECTION_STRING'
              value: serviceBusConnectionString
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
}

// =============================================================================
// Outputs
// =============================================================================

output jobId string = streamProducerJob.id
output jobName string = streamProducerJob.name
