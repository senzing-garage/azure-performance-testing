resource "random_pet" "rg_name" {
  prefix = var.prefix
}

resource "azurerm_resource_group" "rg" {
  name     = "${random_pet.rg_name.id}-rg"
  location = var.resource_group_location
}

resource "azurerm_proximity_placement_group" "ppg" {
  name                = "${random_pet.rg_name.id}-ppg"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

#### NETWORK

# Virtual Network
resource "azurerm_virtual_network" "sz_network" {
  name                = "${random_pet.rg_name.id}-vnet"
  address_space       = ["10.0.0.0/8"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Subnet 1
resource "azurerm_subnet" "sz_subnet_1" {
  name                 = "subnet-1"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.sz_network.name
  address_prefixes     = ["10.240.0.0/16"]
}

resource "azurerm_subnet" "sz_subnet_2" {
  name                 = "subnet-2"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.sz_network.name
  address_prefixes     = ["10.241.0.0/16"]
}

# Public IP address for NAT gateway
# resource "azurerm_public_ip" "sz_public_ip" {
#   name                = "public-ip-nat"
#   location            = azurerm_resource_group.rg.location
#   resource_group_name = azurerm_resource_group.rg.name
#   allocation_method   = "Static"
#   sku                 = "Standard"
# }

# NAT Gateway
# resource "azurerm_nat_gateway" "sz_nat_gateway" {
#   name                = "nat-gateway"
#   location            = azurerm_resource_group.rg.location
#   resource_group_name = azurerm_resource_group.rg.name
# }

# Associate NAT Gateway with Public IP
# resource "azurerm_nat_gateway_public_ip_association" "sz_nat_gateway_public_ip_association" {
#   nat_gateway_id       = azurerm_nat_gateway.sz_nat_gateway.id
#   public_ip_address_id = azurerm_public_ip.sz_public_ip.id
# }

# Associate NAT Gateway with Subnet
# resource "azurerm_subnet_nat_gateway_association" "sz_subnet_nat_gateway_association" {
#   subnet_id      = azurerm_subnet.sz_subnet_1.id
#   nat_gateway_id = azurerm_nat_gateway.sz_nat_gateway.id
# }

# Create public IP for virtual machine (SSH)
# resource "azurerm_public_ip" "sz_public_ip_vm" {
#   name                = "public-ip-vm"
#   location            = azurerm_resource_group.rg.location
#   resource_group_name = azurerm_resource_group.rg.name
#   allocation_method   = "Static"
#   sku                 = "Standard"
# }

# Create Network Security Group and rule for SSH vm
# resource "azurerm_network_security_group" "sz_nsg" {
#   name                = "nsg-1"
#   location            = azurerm_resource_group.rg.location
#   resource_group_name = azurerm_resource_group.rg.name

#   security_rule {
#     name                       = "SSH"
#     priority                   = 1001
#     direction                  = "Inbound"
#     access                     = "Allow"
#     protocol                   = "Tcp"
#     source_port_range          = "*"
#     destination_port_range     = "22"
#     source_address_prefix      = "*"
#     destination_address_prefix = "*"
#   }
# }

# Create network interface for SSH vm
resource "azurerm_network_interface" "sz_nic" {
  name                = "nic-1"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "sz_nic_configuration"
    subnet_id                     = azurerm_subnet.sz_subnet_1.id
    private_ip_address_allocation = "Dynamic"
    # public_ip_address_id          = azurerm_public_ip.sz_public_ip_vm.id
  }
}

# Connect the security group to the network interface for SSH
# resource "azurerm_network_interface_security_group_association" "sz_nic_nsg_association" {
#   network_interface_id      = azurerm_network_interface.sz_nic.id
#   network_security_group_id = azurerm_network_security_group.sz_nsg.id
# }


#### DATABASE

resource "azurerm_mssql_firewall_rule" "firewall" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.server.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Random password for the database
resource "random_password" "db_admin_password" {
  count       = var.db_admin_password == null ? 1 : 0
  length      = 20
  special     = false
  min_numeric = 1
  min_upper   = 1
  min_lower   = 1
  min_special = 0
}

locals {
  db_admin_password = try(random_password.db_admin_password[0].result, var.db_admin_password)
}

# SQL Server
resource "azurerm_mssql_server" "server" {
  name                         = "${random_pet.rg_name.id}-mssql-server"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  administrator_login          = var.db_admin_username
  administrator_login_password = local.db_admin_password
  version                      = "12.0"
  tags = {
    environment = "Production"
  }
}

# SQL Database
resource "azurerm_mssql_database" "db" {
  name      = var.sql_db_name
  server_id = azurerm_mssql_server.server.id
  collation = "Latin1_General_100_CS_AI_SC_UTF8"
  # max_size_gb    = 4
  # read_scale     = true
  sku_name = var.database_sku
  # zone_redundant = true
  # enclave_type   = "VBS"
}


#### STORAGE FOR LOGGING

resource "azurerm_log_analytics_workspace" "sz_logs" {
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  name                = "${random_pet.rg_name.id}-perf-workspace"
}
