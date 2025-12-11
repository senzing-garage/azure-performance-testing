// =============================================================================
// Key Vault Module
// =============================================================================
// Creates Key Vault for storing:
// - Senzing license
// - Azure SQL admin password (for init only)
// - Senzing engine configuration JSON
// =============================================================================

@description('Name of the Key Vault (must be globally unique)')
param name string

@description('Location for the Key Vault')
param location string

@description('Principal ID of the managed identity that needs access')
param managedIdentityPrincipalId string

@description('Senzing license as base64')
@secure()
param senzingLicenseBase64 string

@description('Azure SQL admin password')
@secure()
param sqlPassword string

@description('Senzing engine configuration JSON (password-based)')
@secure()
param senzingConfigPassword string

@description('Senzing engine configuration JSON (managed identity)')
@secure()
param senzingConfigManagedIdentity string

// =============================================================================
// Key Vault
// =============================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    // Note: enablePurgeProtection defaults to false for new vaults
    // Once enabled, it cannot be disabled
    publicNetworkAccess: 'Enabled'
  }
}

// =============================================================================
// RBAC - Grant Managed Identity access to secrets
// =============================================================================

// Key Vault Secrets User role for managed identity
resource secretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, managedIdentityPrincipalId, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// =============================================================================
// Secrets
// =============================================================================

resource secretSenzingLicense 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'senzing-license'
  properties: {
    value: senzingLicenseBase64
    contentType: 'text/plain'
  }
}

resource secretSqlPassword 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'sql-admin-password'
  properties: {
    value: sqlPassword
    contentType: 'text/plain'
  }
}

resource secretSenzingConfigPassword 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'senzing-config-password'
  properties: {
    value: senzingConfigPassword
    contentType: 'application/json'
  }
}

resource secretSenzingConfigMi 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'senzing-config-mi'
  properties: {
    value: senzingConfigManagedIdentity
    contentType: 'application/json'
  }
}

// =============================================================================
// Outputs
// =============================================================================

output vaultId string = keyVault.id
output vaultName string = keyVault.name
output vaultUri string = keyVault.properties.vaultUri
