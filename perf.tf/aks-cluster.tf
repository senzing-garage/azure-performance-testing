resource "azurerm_kubernetes_cluster" "sz_perf_cluster" {
  name                = "${random_pet.rg_name.id}-cluster"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "perfcluster"

  default_node_pool {
    name       = "default"
    node_count = "4"
    # vm_size    = "standard_d5_v2"
    vm_size = "Standard_E8_v3"
    # vm_size                      = "Standard_E16_v3"
    enable_auto_scaling          = true
    min_count                    = 2
    max_count                    = 500 # kubenet limits to 400 nodes
    proximity_placement_group_id = azurerm_proximity_placement_group.ppg.id
    vnet_subnet_id               = azurerm_subnet.sz_subnet_2.id
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Environment = "Production"
  }
}


