// =============================================================================
// Init Database Job Module
// =============================================================================
// Creates Container Apps Job for initializing the Senzing database
// IMPORTANT: Uses PASSWORD authentication because the init-database image
// does not support Managed Identity authentication
// =============================================================================

@description('Name of the job')
param name string

@description('Location for the job')
param location string

@description('Container Apps Environment ID')
param containerAppsEnvId string

@description('Senzing init-database container image')
param image string

@description('Senzing engine configuration JSON (password-based)')
@secure()
param senzingConfigJson string

// =============================================================================
// Container Apps Job - Init Database
// =============================================================================
// Note: This job uses a public Docker Hub image (docker.io/senzing/init-database)
// so it doesn't need ACR registry configuration

resource initDatabaseJob 'Microsoft.App/jobs@2023-05-01' = {
  name: name
  location: location
  properties: {
    environmentId: containerAppsEnvId
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 1800 // 30 minutes
      replicaRetryLimit: 1
      secrets: [
        {
          name: 'senzing-config'
          value: senzingConfigJson
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'init-database'
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
          ]
        }
      ]
    }
  }
}

// Note: Secrets must be defined separately with secretRef
// The Senzing config JSON is passed as environment variable
// This job should be triggered once during deployment via az containerapp job start

// =============================================================================
// Outputs
// =============================================================================

output jobId string = initDatabaseJob.id
output jobName string = initDatabaseJob.name
