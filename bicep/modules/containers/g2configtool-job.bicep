// =============================================================================
// G2ConfigTool Job Module
// =============================================================================
// Creates Container Apps Job for configuring Senzing data sources
// Uses Managed Identity authentication
// =============================================================================

@description('Name of the job')
param name string

@description('Location for the job')
param location string

@description('Container Apps Environment ID')
param containerAppsEnvId string

@description('Senzing SDK tools container image')
param image string

@description('Senzing engine configuration JSON (managed identity)')
@secure()
param senzingConfigJson string

@description('User-assigned Managed Identity resource ID')
param managedIdentityId string

@description('ACR login server (e.g., myacr.azurecr.io) - if provided, configures ACR pull with managed identity')
param acrLoginServer string = ''

// =============================================================================
// Container Apps Job - G2ConfigTool
// =============================================================================

resource g2ConfigToolJob 'Microsoft.App/jobs@2023-05-01' = {
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
      replicaTimeout: 600 // 10 minutes
      replicaRetryLimit: 1
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
          name: 'g2configtool'
          image: image
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
          env: [
            {
              name: 'SENZING_ENGINE_CONFIGURATION_JSON'
              secretRef: 'senzing-config'
            }
          ]
          command: [
            '/bin/bash'
            '-c'
            '''
            echo "Configuring Senzing data sources using sz_configtool..."

            # Use sz_configtool to add data sources non-interactively
            # This matches the AWS CFT EcsTaskDefinitionG2ConfigTool configuration
            echo -e "addDataSource CUSTOMERS\naddDataSource REFERENCE\naddDataSource WATCHLIST\nsave\ny\nquit" | sz_configtool

            echo "Senzing configuration complete"
            '''
          ]
        }
      ]
    }
  }
}

// =============================================================================
// Outputs
// =============================================================================

output jobId string = g2ConfigToolJob.id
output jobName string = g2ConfigToolJob.name
