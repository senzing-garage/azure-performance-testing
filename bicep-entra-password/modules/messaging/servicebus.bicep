// =============================================================================
// Azure Service Bus Module
// =============================================================================
// Creates Service Bus namespace with queues for Senzing:
// - senzing-input: Input queue for StreamLoader
// - senzing-redo: Redo queue for Redoer
// Uses SAS connection strings only (no Managed Identity RBAC)
// =============================================================================

@description('Name of the Service Bus namespace')
param name string

@description('Location for the Service Bus')
param location string

@description('Service Bus SKU: Standard (~$10/month, shared, throttled) or Premium (~$677/month, dedicated, no throttling)')
@allowed([
  'Standard'
  'Premium'
])
param sku string = 'Premium'

// =============================================================================
// Service Bus Namespace
// =============================================================================

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: name
  location: location
  sku: {
    name: sku
    tier: sku
    capacity: sku == 'Premium' ? 1 : null  // 1 Messaging Unit for Premium
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

// =============================================================================
// Queues
// =============================================================================

resource queueInput 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'senzing-input'
  properties: {
    lockDuration: 'PT5M'
    maxSizeInMegabytes: sku == 'Premium' ? 81920 : 5120  // Premium: 80GB, Standard: 5GB
    requiresDuplicateDetection: false
    requiresSession: false
    defaultMessageTimeToLive: 'P14D'
    deadLetteringOnMessageExpiration: true
    maxDeliveryCount: 10
    enablePartitioning: false
    enableBatchedOperations: true
  }
}

resource queueRedo 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'senzing-redo'
  properties: {
    lockDuration: 'PT5M'
    maxSizeInMegabytes: 1024
    requiresDuplicateDetection: false
    requiresSession: false
    defaultMessageTimeToLive: 'P14D'
    deadLetteringOnMessageExpiration: true
    maxDeliveryCount: 10
    enablePartitioning: false
    enableBatchedOperations: true
  }
}

// =============================================================================
// Shared Access Policies (for all service authentication - no MI)
// =============================================================================

resource sendAuthRule 'Microsoft.ServiceBus/namespaces/authorizationRules@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'SendPolicy'
  properties: {
    rights: ['Send']
  }
}

resource listenAuthRule 'Microsoft.ServiceBus/namespaces/authorizationRules@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'ListenPolicy'
  properties: {
    rights: ['Listen']
  }
}

// Manage policy for KEDA autoscaling (requires Manage claim to query queue metrics)
resource manageAuthRule 'Microsoft.ServiceBus/namespaces/authorizationRules@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'ManagePolicy'
  properties: {
    rights: ['Manage', 'Listen', 'Send']
  }
}

// =============================================================================
// Outputs
// =============================================================================

output namespaceId string = serviceBusNamespace.id
output namespaceName string = serviceBusNamespace.name
output inputQueueName string = queueInput.name
output redoQueueName string = queueRedo.name
output endpoint string = serviceBusNamespace.properties.serviceBusEndpoint
output connectionString string = sendAuthRule.listKeys().primaryConnectionString
output listenConnectionString string = listenAuthRule.listKeys().primaryConnectionString
output manageConnectionString string = manageAuthRule.listKeys().primaryConnectionString
