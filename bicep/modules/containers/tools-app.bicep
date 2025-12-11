// =============================================================================
// Senzing Tools Container App Module
// =============================================================================
// Creates Container App for running Senzing tools and debugging
// Features:
// - No external ingress (access via `az containerapp exec`)
// - Managed Identity authentication to Azure SQL
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

@description('Senzing engine configuration JSON (managed identity)')
@secure()
param senzingConfigJson string

@description('User-assigned Managed Identity resource ID')
param managedIdentityId string

@description('ACR login server (e.g., myacr.azurecr.io) - if provided, configures ACR pull with managed identity')
param acrLoginServer string = ''

// =============================================================================
// Container App - Senzing Tools
// =============================================================================

resource toolsApp 'Microsoft.App/containerApps@2023-05-01' = {
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
      // No ingress - access via `az containerapp exec`
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
