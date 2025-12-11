// =============================================================================
// ACR Pull Role Assignment Module
// =============================================================================
// Grants AcrPull role to a managed identity for pulling images from ACR
// This module is deployed to the ACR's resource group via scope
// =============================================================================

@description('Name of the Azure Container Registry')
param acrName string

@description('Principal ID of the managed identity that needs pull access')
param principalId string

// =============================================================================
// Reference existing ACR in this resource group
// =============================================================================

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

// =============================================================================
// Role Assignment
// =============================================================================

// AcrPull built-in role: 7f951dda-4ed3-4680-a7ca-43fe172d538d
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, principalId, 'AcrPull')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
