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

resource "azurerm_mssql_firewall_rule" "firewall" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.server.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

#### DATABASE

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
