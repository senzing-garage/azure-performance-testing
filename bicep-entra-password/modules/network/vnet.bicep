// =============================================================================
// Virtual Network Module
// =============================================================================
// Creates VNet with subnets for Container Apps Environments and Azure SQL
// Three separate Container Apps subnets for independent vCPU quotas:
// - Core: Init jobs, Tools, Redoer (~20 vCPU)
// - Loader: StreamLoader scaling (~70 vCPU with 2 CPU × 35 replicas)
// - Producer: Producer jobs (~50 vCPU with 2 CPU × 25 jobs)
// Includes Private DNS Zone for Azure SQL
// =============================================================================

@description('Name of the virtual network')
param name string

@description('Location for the virtual network')
param location string

@description('Address prefix for the VNet')
param addressPrefix string

@description('Address prefix for Core Container Apps subnet (init jobs, tools, redoer)')
param containerAppsCoreSubnetPrefix string

@description('Address prefix for Loader Container Apps subnet (streamloader)')
param containerAppsLoaderSubnetPrefix string

@description('Address prefix for Producer Container Apps subnet (producer jobs)')
param containerAppsProducerSubnetPrefix string

@description('Address prefix for Azure SQL subnet (for private endpoint)')
param sqlSubnetPrefix string

// =============================================================================
// Virtual Network
// =============================================================================

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: name
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        // Core Container Apps Environment: init jobs, tools, redoer
        // Each environment needs its own subnet (minimum /23)
        name: 'container-apps-core-subnet'
        properties: {
          addressPrefix: containerAppsCoreSubnetPrefix
        }
      }
      {
        // Loader Container Apps Environment: streamloader with high scaling
        name: 'container-apps-loader-subnet'
        properties: {
          addressPrefix: containerAppsLoaderSubnetPrefix
        }
      }
      {
        // Producer Container Apps Environment: producer jobs
        name: 'container-apps-producer-subnet'
        properties: {
          addressPrefix: containerAppsProducerSubnetPrefix
        }
      }
      {
        // Azure SQL uses private endpoints, not subnet delegation
        name: 'sql-subnet'
        properties: {
          addressPrefix: sqlSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// =============================================================================
// Private DNS Zone for Azure SQL
// =============================================================================

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink${environment().suffixes.sqlServerHostname}'
  location: 'global'
}

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: '${name}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

// =============================================================================
// Outputs
// =============================================================================

output vnetId string = vnet.id
output vnetName string = vnet.name
output containerAppsCoreSubnetId string = vnet.properties.subnets[0].id
output containerAppsLoaderSubnetId string = vnet.properties.subnets[1].id
output containerAppsProducerSubnetId string = vnet.properties.subnets[2].id
output sqlSubnetId string = vnet.properties.subnets[3].id
output privateDnsZoneId string = privateDnsZone.id
