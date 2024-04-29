
resource "azurerm_servicebus_namespace" "sz_service_bus" {
  name                = "${random_pet.rg_name.id}-service-bus"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"

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
  enable_partitioning                  = true
  lock_duration                        = "PT5M"
}

