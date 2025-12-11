// =============================================================================
// Redoer Container App Module
// =============================================================================
// Creates Container App for reprocessing redo records
// Features:
// - KEDA auto-scaling based on timer or redo queue
// - Managed Identity authentication to PostgreSQL
// - Processes redo records to maintain data quality
// =============================================================================

@description('Name of the Container App')
param name string

@description('Location for the app')
param location string

@description('Container Apps Environment ID')
param containerAppsEnvId string

@description('Redoer container image')
param image string

@description('Senzing engine configuration JSON (managed identity)')
@secure()
param senzingConfigJson string

@description('User-assigned Managed Identity resource ID')
param managedIdentityId string

@description('Maximum number of replicas')
param maxReplicas int

@description('ACR login server (e.g., myacr.azurecr.io) - if provided, configures ACR pull with managed identity')
param acrLoginServer string = ''

// =============================================================================
// Container App - Redoer
// =============================================================================

resource redoerApp 'Microsoft.App/containerApps@2023-05-01' = {
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
          name: 'redoer'
          image: image
          resources: {
            cpu: json('2.0')
            memory: '4Gi'
          }
          env: [
            {
              name: 'SENZING_ENGINE_CONFIGURATION_JSON'
              secretRef: 'senzing-config'
            }
            {
              name: 'SENZING_THREADS_PER_PROCESS'
              value: '4'
            }
            {
              name: 'SENZING_REDO_SLEEP_TIME_IN_SECONDS'
              value: '60'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: maxReplicas
        rules: [
          {
            // Scale based on CPU utilization
            name: 'cpu-scale'
            custom: {
              type: 'cpu'
              metadata: {
                type: 'Utilization'
                value: '70'
              }
            }
          }
        ]
      }
    }
  }
}

// =============================================================================
// Outputs
// =============================================================================

output appId string = redoerApp.id
output appName string = redoerApp.name
output fqdn string = redoerApp.properties.latestRevisionFqdn
