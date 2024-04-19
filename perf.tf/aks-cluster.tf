resource "azurerm_kubernetes_cluster" "sz_perf_cluster" {
  name                = "${random_pet.rg_name.id}-cluster"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "perfcluster"

  default_node_pool {
    name       = "default"
    node_count = "2"
    # vm_size    = "standard_d5_v2"
    vm_size = "Standard_E8_v3"
  }

  identity {
    type = "SystemAssigned"
  }
}

