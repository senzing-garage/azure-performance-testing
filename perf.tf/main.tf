resource "random_pet" "rg_name" {
  prefix = var.prefix
}

resource "azurerm_resource_group" "rg" {
  name     = "${random_pet.rg_name.id}-rg"
  location = var.resource_group_location
}

# resource "random_pet" "azurerm_mssql_server_name" {
#   prefix = "sql"
# }

#### NETWORK

# Virtual Network
resource "azurerm_virtual_network" "sz_network" {
  name                = "${random_pet.rg_name.id}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Subnet 1
resource "azurerm_subnet" "sz_subnet_1" {
  name                 = "subnet-1"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.sz_network.name
  address_prefixes     = ["10.0.0.0/24"]
}

# Public IP address for NAT gateway
resource "azurerm_public_ip" "sz_public_ip" {
  name                = "public-ip-nat"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# NAT Gateway
resource "azurerm_nat_gateway" "sz_nat_gateway" {
  name                = "nat-gateway"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Associate NAT Gateway with Public IP
resource "azurerm_nat_gateway_public_ip_association" "sz_nat_gateway_public_ip_association" {
  nat_gateway_id       = azurerm_nat_gateway.sz_nat_gateway.id
  public_ip_address_id = azurerm_public_ip.sz_public_ip.id
}

# Associate NAT Gateway with Subnet
resource "azurerm_subnet_nat_gateway_association" "sz_subnet_nat_gateway_association" {
  subnet_id      = azurerm_subnet.sz_subnet_1.id
  nat_gateway_id = azurerm_nat_gateway.sz_nat_gateway.id
}

resource "azurerm_mssql_firewall_rule" "firewall" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.server.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Create public IP for virtual machine (SSH)
resource "azurerm_public_ip" "sz_public_ip_vm" {
  name                = "public-ip-vm"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Create Network Security Group and rule for SSH vm
resource "azurerm_network_security_group" "sz_nsg" {
  name                = "nsg-1"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Create network interface for SSH vm
resource "azurerm_network_interface" "sz_nic" {
  name                = "nic-1"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "sz_nic_configuration"
    subnet_id                     = azurerm_subnet.sz_subnet_1.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.sz_public_ip_vm.id
  }
}

# Connect the security group to the network interface for SSH
resource "azurerm_network_interface_security_group_association" "sz_nic_nsg_association" {
  network_interface_id      = azurerm_network_interface.sz_nic.id
  network_security_group_id = azurerm_network_security_group.sz_nsg.id
}

#### DATABASE

# Random password for the database
resource "random_password" "db_admin_password" {
  count       = var.db_admin_password == null ? 1 : 0
  length      = 20
  special     = true
  min_numeric = 1
  min_upper   = 1
  min_lower   = 1
  min_special = 1
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
}

# SQL Database
resource "azurerm_mssql_database" "db" {
  name      = var.sql_db_name
  server_id = azurerm_mssql_server.server.id
  # max_size_gb    = 4
  # read_scale     = true
  # sku_name       = "S0"
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

# Generate random text for a unique storage account name
resource "random_id" "random_id" {
  keepers = {
    # Generate a new ID only when a new resource group is defined
    resource_group = azurerm_resource_group.rg.name
  }

  byte_length = 8
}

# Create storage account for boot diagnostics
resource "azurerm_storage_account" "sz_storage_account" {
  name                     = "szlogs${random_id.random_id.hex}"
  location                 = azurerm_resource_group.rg.location
  resource_group_name      = azurerm_resource_group.rg.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_share" "sz_share" {
  name = "${random_pet.rg_name.id}-share"
  storage_account_name = azurerm_storage_account.sz_storage_account.name
  quota = 50
}

#### CONTAINERS

# Container Group
resource "azurerm_container_group" "cg" {
  name                = "${random_pet.rg_name.id}-cg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_address_type     = "Private"
  subnet_ids = azurerm_subnet.sz_subnet_1[*].id
  # ip_address_type     = "Public"
  # dns_name_label      = "${random_pet.rg_name.id}-cg"
  os_type             = "Linux"
  depends_on          = [azurerm_mssql_database.db]
  diagnostics {
    log_analytics {
      log_type = "ContainerInsights"
      workspace_id = azurerm_log_analytics_workspace.sz_logs.workspace_id
      workspace_key = azurerm_log_analytics_workspace.sz_logs.primary_shared_key
    }
  }

  # init_container {
  #   name  = "init-database"
  #   image = "docker.io/senzing/init-database:0.5.2"

  #   environment_variables = {
  #     SENZING_TOOLS_ENGINE_CONFIGURATION_JSON = <<EOT
  #       {
  #           "PIPELINE": {
  #               "CONFIGPATH": "/etc/opt/senzing",
  #               "LICENSESTRINGBASE64": "{license_string}",
  #               "RESOURCEPATH": "/opt/senzing/g2/resources",
  #               "SUPPORTPATH": "/opt/senzing/data"
  #           },
  #           "SQL": {
  #               "BACKEND": "SQL",
  #               "CONNECTION" : "mssql://${azurerm_mssql_server.server.administrator_login}:${local.db_admin_password}@${azurerm_mssql_server.server.fully_qualified_domain_name}:1433/${azurerm_mssql_database.db.name}"
  #           }
  #       }
  #     EOT
  #     LC_CTYPE                                = "en_US.utf8"
  #     SENZING_SUBCOMMAND                      = "mandatory"
  #     SENZING_DEBUG                           = "False"
  #   }
  #   volume {
  #     name = "logs"
  #     mount_path = "/mnt/logs"
  #     read_only = false
  #     share_name = azurerm_storage_share.sz_share.name
  #     storage_account_name = azurerm_storage_account.sz_storage_account.name
  #     storage_account_key  = azurerm_storage_account.sz_storage_account.primary_access_key
  #   }
  # }

  container {
    name  = "senzingapi-tools"
    image = "docker.io/senzing/senzingapi-tools:3.9.0"
    cpu    = "0.5"
    memory = "1.5"
    # ports {
    #   port     = 80
    #   protocol = "TCP"
    # }

    environment_variables = {
      SENZING_TOOLS_ENGINE_CONFIGURATION_JSON = <<EOT
        {
            "PIPELINE": {
                "CONFIGPATH": "/etc/opt/senzing",
                "LICENSESTRINGBASE64": "{license_string}",
                "RESOURCEPATH": "/opt/senzing/g2/resources",
                "SUPPORTPATH": "/opt/senzing/data"
            },
            "SQL": {
                "BACKEND": "SQL",
                "CONNECTION" : "mssql://${azurerm_mssql_server.server.administrator_login}:${local.db_admin_password}@${azurerm_mssql_server.server.fully_qualified_domain_name}:1433/${azurerm_mssql_database.db.name}"
            }
        }
      EOT
      LC_CTYPE                                = "en_US.utf8"
      SENZING_SUBCOMMAND                      = "mandatory"
      SENZING_DEBUG                           = "False"
    }
    volume {
      name = "logs"
      mount_path = "/mnt/logs"
      read_only = false
      share_name = azurerm_storage_share.sz_share.name
      storage_account_name = azurerm_storage_account.sz_storage_account.name
      storage_account_key  = azurerm_storage_account.sz_storage_account.primary_access_key
    }
  }

# Error: creating Container Group (Subscription: "5415bf99-6956-43fd-a8a9-434c958ca13c"
# │ Resource Group Name: "sz-sterling-oyster-rg"
# │ Container Group Name: "sz-sterling-oyster-cg"): performing ContainerGroupsCreateOrUpdate: containerinstance.ContainerInstanceClient#ContainerGroupsCreateOrUpdate: Failure sending request: StatusCode=0 -- Original Error: Code="MissingIpAddressPorts" Message="The ports in the 'ipAddress' of container group 'sz-sterling-oyster-cg' cannot be empty."
# │
# │   with azurerm_container_group.cg,
# │   on main.tf line 192, in resource "azurerm_container_group" "cg":
# │  192: resource "azurerm_container_group" "cg" {

  # container {
  #   name   = "hw"
  #   image  = "mcr.microsoft.com/azuredocs/aci-helloworld:latest"
  #   cpu    = "0.5"
  #   memory = "1.5"

  #   ports {
  #     port     = 80
  #     protocol = "TCP"
  #   }
  #   volume {
  #     name = "logs"
  #     mount_path = "/mnt/logs"
  #     read_only = false
  #     share_name = azurerm_storage_share.sz_share.name
  #     storage_account_name = azurerm_storage_account.sz_storage_account.name
  #     storage_account_key  = azurerm_storage_account.sz_storage_account.primary_access_key
  #   }
  # }

  tags = {
    environment = "testing"
  }
}