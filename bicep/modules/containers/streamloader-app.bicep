// =============================================================================
// StreamLoader Container App Module
// =============================================================================
// Creates Container App for loading records from Service Bus queue
// Features:
// - KEDA auto-scaling based on Service Bus queue length
// - Managed Identity authentication to PostgreSQL
// - Scales to zero when no messages
// =============================================================================

@description('Name of the Container App')
param name string

@description('Location for the app')
param location string

@description('Container Apps Environment ID')
param containerAppsEnvId string

@description('StreamLoader container image')
param image string

@description('Senzing engine configuration JSON (managed identity)')
@secure()
param senzingConfigJson string

@description('User-assigned Managed Identity resource ID')
param managedIdentityId string

@description('Service Bus namespace name (for KEDA scaling)')
param serviceBusNamespace string

@description('Service Bus queue name')
param serviceBusQueueName string

@description('Service Bus connection string for consuming messages (Listen rights)')
@secure()
param serviceBusConnectionString string

@description('Service Bus connection string for KEDA scaling (Manage rights required to query queue metrics)')
@secure()
param serviceBusManageConnectionString string

@description('Minimum number of replicas')
param minReplicas int = 0

@description('Maximum number of replicas')
param maxReplicas int

@description('ACR login server (e.g., myacr.azurecr.io) - if provided, configures ACR pull with managed identity')
param acrLoginServer string = ''

// =============================================================================
// Container App - StreamLoader
// =============================================================================

// Scale rules for Service Bus queue-based scaling
// KEDA needs Manage rights to query queue metrics for autoscaling
var scaleRules = [
  {
    name: 'servicebus-scale'
    custom: {
      type: 'azure-servicebus'
      metadata: {
        queueName: serviceBusQueueName
        namespace: serviceBusNamespace
        messageCount: '100'
      }
      auth: [
        {
          secretRef: 'servicebus-manage'
          triggerParameter: 'connection'
        }
      ]
    }
  }
]

resource streamLoaderApp 'Microsoft.App/containerApps@2023-05-01' = {
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
      activeRevisionsMode: 'Single'
      secrets: [
        {
          name: 'senzing-config'
          value: senzingConfigJson
        }
        {
          name: 'servicebus-connection'
          value: serviceBusConnectionString
        }
        {
          name: 'servicebus-manage'
          value: serviceBusManageConnectionString
        }
      ]
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
          name: 'stream-loader'
          image: image
          resources: {
            // With dedicated Loader environment, each loader can use full resources
            // 2 CPU / 4Gi allows for better throughput when processing records
            cpu: json('2.0')
            memory: '4Gi'
          }
          env: [
            {
              name: 'SENZING_ENGINE_CONFIGURATION_JSON'
              secretRef: 'senzing-config'
            }
            {
              name: 'SENZING_AZURE_QUEUE_CONNECTION_STRING'
              secretRef: 'servicebus-connection'
            }
            {
              name: 'SENZING_AZURE_QUEUE_NAME'
              value: serviceBusQueueName
            }
            {
              name: 'SENZING_THREADS_PER_PROCESS'
              value: '4'
            }
          ]
        }
      ]
      // Scale based on Service Bus queue depth
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: scaleRules
      }
    }
  }
}

// =============================================================================
// Outputs
// =============================================================================

output appId string = streamLoaderApp.id
output appName string = streamLoaderApp.name
output fqdn string = streamLoaderApp.properties.latestRevisionFqdn
