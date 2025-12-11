// =============================================================================
// G2ConfigTool Job Module
// =============================================================================
// Creates Container Apps Job for configuring Senzing data sources
// Uses Entra ID Password authentication (no Managed Identity)
// =============================================================================

@description('Name of the job')
param name string

@description('Location for the job')
param location string

@description('Container Apps Environment ID')
param containerAppsEnvId string

@description('Senzing SDK tools container image')
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
// Container Apps Job - G2ConfigTool
// =============================================================================

resource g2ConfigToolJob 'Microsoft.App/jobs@2023-05-01' = {
  name: name
  location: location
  properties: {
    environmentId: containerAppsEnvId
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 600 // 10 minutes
      replicaRetryLimit: 1
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
