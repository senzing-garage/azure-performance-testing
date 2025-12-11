// =============================================================================
// Senzing Tools Container App Module
// =============================================================================
// Creates Container App for running Senzing tools and debugging
// Features:
// - No external ingress (access via `az containerapp exec`)
// - Entra ID Password authentication to Azure SQL (no MI)
// - Single replica (always running for instant access)
// =============================================================================

@description('Name of the Container App')
param name string

@description('Location for the app')
param location string

@description('Container Apps Environment ID')
param containerAppsEnvId string

@description('Senzing tools container image')
param image string

@description('Senzing engine configuration JSON')
@secure()
param senzingConfigJson string

@description('ACR login server (e.g., myacr.azurecr.io)')
param acrLoginServer string = ''

@description('ACR username (token name or admin username)')
param acrUsername string = ''

@description('ACR password (token password or admin password)')
@secure()
param acrPassword string = ''

// =============================================================================
// Container App - Senzing Tools
// =============================================================================

resource toolsApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: name
  location: location
  properties: {
    environmentId: containerAppsEnvId
    configuration: {
      activeRevisionsMode: 'Single'
      // No ingress - access via `az containerapp exec`
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
          name: 'tools'
          image: image
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
          // Keep container alive for `az containerapp exec` access
          command: ['/bin/bash', '-c', 'sleep infinity']
          env: [
            {
              name: 'SENZING_ENGINE_CONFIGURATION_JSON'
              secretRef: 'senzing-config'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

// =============================================================================
// Outputs
// =============================================================================

output appId string = toolsApp.id
output appName string = toolsApp.name
