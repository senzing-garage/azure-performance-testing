// =============================================================================
// Azure SQL Database Module
// =============================================================================
// Creates Azure SQL Server and Database with:
// - SQL authentication for initial setup
// - Entra ID Password authentication for runtime (no MI required)
// - Private endpoint for VNet integration
// - Performance tuning for Senzing workloads
// =============================================================================

@description('Name of the SQL Server (will be globally unique)')
param name string

@description('Location for the server')
param location string

@description('Administrator login name')
param administratorLogin string

@description('Administrator password')
@secure()
param administratorPassword string

@description('SKU name for the database (e.g., GP_Gen5_8 for General Purpose)')
param skuName string

@description('Max size in GB')
param maxSizeGB int

@description('Name of the database to create')
param databaseName string

@description('Subnet ID for private endpoint')
param subnetId string

@description('Private DNS Zone ID')
param privateDnsZoneId string

@description('Entra ID user email for Azure AD administrator')
param entraUserEmail string = ''

@description('Entra ID user Object ID for Azure AD administrator')
param entraUserObjectId string = ''

// =============================================================================
// SQL Server
// =============================================================================

resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {
  name: name
  location: location
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorPassword
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Disabled'
  }
}

// =============================================================================
// Azure AD Administrator
// =============================================================================
// Required for any Entra ID authentication (including ActiveDirectoryPassword)
// The Entra user is set as the Azure AD admin

resource aadAdmin 'Microsoft.Sql/servers/administrators@2023-05-01-preview' = if (!empty(entraUserEmail) && !empty(entraUserObjectId)) {
  parent: sqlServer
  name: 'ActiveDirectory'
  properties: {
    administratorType: 'ActiveDirectory'
    login: entraUserEmail
    sid: entraUserObjectId
    tenantId: subscription().tenantId
  }
}

// =============================================================================
// Database
// =============================================================================

resource database 'Microsoft.Sql/servers/databases@2023-05-01-preview' = {
  parent: sqlServer
  name: databaseName
  location: location
  sku: {
    name: skuName
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: maxSizeGB * 1024 * 1024 * 1024
    catalogCollation: 'SQL_Latin1_General_CP1_CI_AS'
    zoneRedundant: false
    readScale: 'Disabled'
    requestedBackupStorageRedundancy: 'Local'
  }
}

// =============================================================================
// Private Endpoint
// =============================================================================

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: '${name}-pe'
  location: location
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${name}-plsc'
        properties: {
          privateLinkServiceId: sqlServer.id
          groupIds: [
            'sqlServer'
          ]
        }
      }
    ]
  }
}

// =============================================================================
// Private DNS Zone Group
// =============================================================================

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-database-windows-net'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

// =============================================================================
// Outputs
// =============================================================================

output serverId string = sqlServer.id
output serverName string = sqlServer.name
output fqdn string = sqlServer.properties.fullyQualifiedDomainName
output databaseName string = database.name
output databaseId string = database.id
