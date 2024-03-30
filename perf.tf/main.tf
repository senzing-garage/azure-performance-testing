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
  name                         = "${random_pet.rg_name.id}-mssql-server"
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

resource "azurerm_container_group" "cg" {
  name                = "${random_pet.rg_name.id}-cg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_address_type     = "Public"
  dns_name_label      = "${random_pet.rg_name.id}-cg"
  os_type             = "Linux"
  depends_on = [ azurerm_mssql_database.db ]

  init_container {
    name   = "init-database"
    image  = "docker.io/senzing/init-database:0.5.2"

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
      LC_CTYPE = "en_US.utf8"
      SENZING_SUBCOMMAND = "mandatory"
      SENZING_DEBUG = "False"
    }
  }

  container {
    name   = "hw"
    image  = "mcr.microsoft.com/azuredocs/aci-helloworld:latest"
    cpu    = "0.5"
    memory = "1.5"

    ports {
      port     = 80
      protocol = "TCP"
    }
  }

  tags = {
    environment = "testing"
  }
}