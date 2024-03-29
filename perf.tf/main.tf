# resource "random_pet" "rg_name" {
#   prefix = var.resource_group_name_prefix
# }

resource "azurerm_resource_group" "rg" {
#   name     = random_pet.rg_name.id
  name     = "rg-senzing"
  location = var.resource_group_location
}

# resource "random_pet" "azurerm_mssql_server_name" {
#   prefix = "sql"
# }

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

resource "azurerm_mssql_server" "server" {
#   name                         = random_pet.azurerm_mssql_server_name.id
  name                         = "senzing-sql-server"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  administrator_login          = var.db_admin_username
  administrator_login_password = local.db_admin_password
  version                      = "12.0"
}

resource "azurerm_mssql_database" "db" {
  name      = var.sql_db_name
  server_id = azurerm_mssql_server.server.id
}