// =============================================================================
// Redoer Container App Module
// =============================================================================
// Creates Container App for reprocessing redo records
// Features:
// - KEDA auto-scaling based on CPU
// - Entra ID Password authentication to Azure SQL (no MI)
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

@description('Senzing engine configuration JSON')
@secure()
param senzingConfigJson string

@description('Maximum number of replicas')
param maxReplicas int

@description('ACR login server (e.g., myacr.azurecr.io)')
param acrLoginServer string = ''

@description('ACR username (token name or admin username)')
param acrUsername string = ''

@description('ACR password (token password or admin password)')
@secure()
param acrPassword string = ''

// =============================================================================
// Container App - Redoer
// =============================================================================

resource redoerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: name
  location: location
  properties: {
    environmentId: containerAppsEnvId
    configuration: {
      activeRevisionsMode: 'Single'
      secrets: concat([
        {
          name: 'senzing-config'
          value: senzingConfigJson
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
