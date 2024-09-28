
resource "azurerm_servicebus_namespace" "sz_service_bus" {
  name                         = "${random_pet.rg_name.id}-service-bus"
  location                     = azurerm_resource_group.rg.location
  resource_group_name          = azurerm_resource_group.rg.name
  sku                          = "Premium"
  capacity                     = 2
  premium_messaging_partitions = 2

  # network_rule_set {
  #   default_action                = "Deny"
  #   public_network_access_enabled = true
  #   ip_rules                      = ["71.62.190.73"]

  # }
}

resource "azurerm_servicebus_queue" "sz_queue" {
  name         = "${random_pet.rg_name.id}-queue"
  namespace_id = azurerm_servicebus_namespace.sz_service_bus.id

  dead_lettering_on_message_expiration = true
  # enable_partitioning is deprecated, but partitioning_enabled doesn't work?!
  enable_partitioning = true
  # partitioning_enabled = true
  lock_duration = "PT5M"
}

