locals {
  senzing_engine_configuration_json = <<EOT
        {
            "PIPELINE": {
                "CONFIGPATH": "/etc/opt/senzing",
                "LICENSESTRINGBASE64": "{license_string}",
                "RESOURCEPATH": "/opt/senzing/g2/resources",
                "SUPPORTPATH": "/opt/senzing/data"
            },
            "SQL": {
                "BACKEND": "SQL",
                "DEBUGLEVEL": "2",
                "CONNECTION" : "mssql://${azurerm_mssql_server.server.administrator_login}:${urlencode(local.db_admin_password)}@${azurerm_mssql_server.server.fully_qualified_domain_name}:1433:${azurerm_mssql_database.db.name}"
            }
        }
        EOT
}

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
      image   = var.senzingapi-tools-image
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

    # Senzing Producer, sends data to Azure Queue
    init_container {
      name   = "${random_pet.rg_name.id}-senzing-producer"
      image  = var.senzing-producer-image
      cpu    = 0.5
      memory = "1.0Gi"
      # command = ["/bin/bash", "-c", "while true; do echo grumble $(date); sleep 600;done"]

      env {
        name  = "AZURE_ANIMAL"
        value = random_pet.rg_name.id
      }
      env {
        name  = "LC_CTYPE"
        value = "en_US.utf8"
      }
      env {
        name  = "SENZING_AZURE_QUEUE_CONNECTION_STRING"
        value = azurerm_servicebus_namespace.sz_service_bus.default_primary_connection_string
      }
      env {
        name  = "SENZING_AZURE_QUEUE_NAME"
        value = azurerm_servicebus_queue.sz_queue.name
      }
      env {
        name  = "SENZING_DEFAULT_DATA_SOURCE"
        value = "TEST"
      }
      env {
        name  = "SENZING_DEFAULT_ENTITY_TYPE"
        value = "GENERIC"
      }
      env {
        name  = "SENZING_INPUT_URL"
        value = var.test_data_url
      }
      env {
        name  = "SENZING_MONITORING_PERIOD_IN_SECONDS"
        value = "60"
      }
      env {
        name  = "SENZING_READ_QUEUE_MAXSIZE"
        value = "200"
      }
      env {
        name  = "SENZING_RECORD_MAX"
        value = var.number_of_records
      }
      env {
        name  = "SENZING_RECORD_MIN"
        value = "0"
      }
      env {
        name  = "SENZING_RECORD_MONITOR"
        value = "100000"
      }
      env {
        name  = "SENZING_RECORDS_PER_MESSAGE"
        value = "1"
      }
      env {
        name  = "SENZING_SUBCOMMAND"
        value = "gzipped-json-to-azure-queue"
      }
      env {
        name  = "SENZING_THREADS_PER_PRINT"
        value = "30"
      }
    }

    # Senzing API Tools, used to inspect the database and run tool commands
    container {
      name    = "${random_pet.rg_name.id}-senzingapi-tools"
      image   = var.senzingapi-tools-image
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

######################################################
# container app for loading data into the database
resource "azurerm_container_app" "sz_perf_app" {
  name = "${random_pet.rg_name.id}-ca"

  container_app_environment_id = azurerm_container_app_environment.sz_perf_app_env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"
  depends_on                   = [azurerm_container_app.sz_init_database_app]
  template {

    # Senzing API Tools, used to inspect the database and run tool commands
    container {
      name    = "${random_pet.rg_name.id}-senzing-loader"
      image   = var.senzing-loader-image
      cpu     = 2
      memory  = "4.0Gi"
      command = ["/bin/bash", "-c", var.init_loader_command]

      env {
        name  = "AZURE_ANIMAL"
        value = random_pet.rg_name.id
      }
      env {
        name  = "LC_CTYPE"
        value = "en_US.utf8"
      }
      env {
        name  = "SENZING_AZURE_QUEUE_CONNECTION_STRING"
        value = azurerm_servicebus_namespace.sz_service_bus.default_primary_connection_string
      }
      env {
        name  = "SENZING_AZURE_QUEUE_NAME"
        value = azurerm_servicebus_queue.sz_queue.name
      }
      env {
        name  = "SENZING_DEBUG"
        value = "False"
      }
      env {
        name  = "SENZING_DELAY_IN_SECONDS"
        value = "900"
      }
      env {
        name  = "SENZING_DELAY_RANDOMIZED"
        value = "true"
      }
      env {
        name  = "SENZING_ENGINE_CONFIGURATION_JSON"
        value = local.senzing_engine_configuration_json
      }
      env {
        name  = "SENZING_GOVERNOR_CHECK_TIME_INTERVAL_IN_SECONDS"
        value = "600"
      }
      env {
        name  = "SENZING_LOG_LEVEL"
        value = "info"
      }
      env {
        name  = "SENZING_MONITORING_PERIOD_IN_SECONDS"
        value = "600"
      }
      env {
        name  = "SENZING_PRIME_ENGINE"
        value = "true"
      }
      env {
        name  = "SENZING_SKIP_DATABASE_PERFORMANCE_TEST"
        value = "true"
      }
      env {
        name  = "SENZING_SUBCOMMAND"
        value = "azure-queue"
      }
      env {
        name  = "SENZING_THREADS_PER_PROCESS"
        value = "20"
      }
    }
  }
}
