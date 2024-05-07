
resource "azurerm_container_app_environment" "sz_perf_app_env" {
  name                       = "${random_pet.rg_name.id}-cae"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.sz_logs.id
}

######################################################
# database initialization container app
resource "azurerm_container_app" "sz_init_database_app" {
  name = "${random_pet.rg_name.id}-init-db-ca"

  container_app_environment_id = azurerm_container_app_environment.sz_perf_app_env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"


  template {

    # Senzing Init Container, used to initialize the database
    init_container {
      name    = "${random_pet.rg_name.id}-init-database"
      image   = var.senzingapi_tools_image
      cpu     = 0.5
      memory  = "1.0Gi"
      command = ["/bin/bash", "-c", var.db_init_command]

      env {
        name  = "AZURE_ANIMAL"
        value = random_pet.rg_name.id
      }
      env {
        name  = "LC_CTYPE"
        value = "en_US.utf8"
      }
      env {
        name  = "SENZING_DB_PWD"
        value = local.db_admin_password
      }
      env {
        name  = "SENZING_DEBUG"
        value = "False"
      }
      env {
        name  = "SENZING_ENGINE_CONFIGURATION_JSON"
        value = local.senzing_engine_configuration_json
      }
      env {
        name  = "SENZING_SUBCOMMAND"
        value = "mandatory"
      }
    }

    # Senzing API Tools, used to inspect the database and run tool commands
    container {
      name    = "${random_pet.rg_name.id}-senzingapi-tools"
      image   = var.senzingapi_tools_image
      cpu     = 0.5
      memory  = "1.0Gi"
      command = ["/bin/bash", "-c", var.use_mstools_init_command]

      env {
        name  = "AZURE_ANIMAL"
        value = random_pet.rg_name.id
      }
      env {
        name  = "LC_CTYPE"
        value = "en_US.utf8"
      }
      env {
        name  = "SENZING_DEBUG"
        value = "False"
      }
      env {
        name  = "SENZING_DB_PWD"
        value = local.db_admin_password
      }
      env {
        name  = "SENZING_ENGINE_CONFIGURATION_JSON"
        value = local.senzing_engine_configuration_json
      }
      env {
        name  = "SENZING_SUBCOMMAND"
        value = "mandatory"
      }
    }
  }
}
