// =============================================================================
// Azure Service Bus Module
// =============================================================================
// Creates Service Bus namespace with queues for Senzing:
// - senzing-input: Input queue for StreamLoader
// - senzing-redo: Redo queue for Redoer
// =============================================================================

@description('Name of the Service Bus namespace')
param name string

@description('Location for the Service Bus')
param location string

@description('Principal ID of the managed identity that needs access')
param managedIdentityPrincipalId string

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
// RBAC - Grant Managed Identity access
// =============================================================================

// Azure Service Bus Data Sender role
resource dataSenderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusNamespace.id, managedIdentityPrincipalId, 'Service Bus Data Sender')
  scope: serviceBusNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39') // Azure Service Bus Data Sender
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Azure Service Bus Data Receiver role
resource dataReceiverRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusNamespace.id, managedIdentityPrincipalId, 'Service Bus Data Receiver')
  scope: serviceBusNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0') // Azure Service Bus Data Receiver
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// =============================================================================
// Shared Access Policy (for stream-producer which doesn't support MI)
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
