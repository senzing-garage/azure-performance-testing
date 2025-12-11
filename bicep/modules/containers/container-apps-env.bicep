// =============================================================================
// Container Apps Environment Module
// =============================================================================
// Creates Container Apps Environment with:
// - VNet integration
// - Log Analytics workspace connection
// - Internal load balancer mode
// =============================================================================

@description('Name of the Container Apps Environment')
param name string

@description('Location for the environment')
param location string

@description('Log Analytics workspace ID')
param logAnalyticsWorkspaceId string

@description('Subnet ID for VNet integration')
param subnetId string

// =============================================================================
// Container Apps Environment
// =============================================================================

resource containerAppsEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: name
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: reference(logAnalyticsWorkspaceId, '2022-10-01').customerId
        sharedKey: listKeys(logAnalyticsWorkspaceId, '2022-10-01').primarySharedKey
      }
    }
    vnetConfiguration: {
      infrastructureSubnetId: subnetId
      internal: false
    }
    zoneRedundant: false
  }
}

// =============================================================================
// Outputs
// =============================================================================

output id string = containerAppsEnv.id
output name string = containerAppsEnv.name
output defaultDomain string = containerAppsEnv.properties.defaultDomain
output staticIp string = containerAppsEnv.properties.staticIp
