// =============================================================================
// Managed Identity Module
// =============================================================================
// Creates User-Assigned Managed Identity for Senzing services
// This identity is used for:
// - Azure AD authentication to PostgreSQL
// - Key Vault secret access
// - Service Bus access
// =============================================================================

@description('Name of the managed identity')
param name string

@description('Location for the managed identity')
param location string

// =============================================================================
// User-Assigned Managed Identity
// =============================================================================

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: name
  location: location
}

// =============================================================================
// Outputs
// =============================================================================

output id string = managedIdentity.id
output name string = managedIdentity.name
output principalId string = managedIdentity.properties.principalId
output clientId string = managedIdentity.properties.clientId
output tenantId string = managedIdentity.properties.tenantId
