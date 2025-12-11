// =============================================================================
// Log Analytics Workspace Module
// =============================================================================
// Creates Log Analytics workspace for Container Apps logging
// =============================================================================

@description('Name of the Log Analytics workspace')
param name string

@description('Location for the workspace')
param location string

@description('Retention period in days')
param retentionInDays int = 30

// =============================================================================
// Log Analytics Workspace
// =============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: name
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: -1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// =============================================================================
// Outputs
// =============================================================================

output workspaceId string = logAnalyticsWorkspace.id
output workspaceName string = logAnalyticsWorkspace.name
output customerId string = logAnalyticsWorkspace.properties.customerId
