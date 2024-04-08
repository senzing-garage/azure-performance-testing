resource "azurerm_container_app_environment" "sz_perf_app_env" {
  name                       = "${random_pet.rg_name.id}-cae"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.sz_logs.id
}

resource "azurerm_container_app" "sz_perf_app" {
  name = "${random_pet.rg_name.id}-ca"

  container_app_environment_id = azurerm_container_app_environment.sz_perf_app_env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"

  template {
    init_container {
      name   = "${random_pet.rg_name.id}-init-database"
      image  = var.senzingapi-tools-image
      cpu    = 0.5
      memory = "1Gi"
      command = ["/bin/bash", "-c", var.db_init_command]

      env {
        name  = "SENZING_ENGINE_CONFIGURATION_JSON"
        value = <<EOT
        {
            "PIPELINE": {
                "CONFIGPATH": "/etc/opt/senzing",
                "LICENSESTRINGBASE64": "{license_string}",
                "RESOURCEPATH": "/opt/senzing/g2/resources",
                "SUPPORTPATH": "/opt/senzing/data"
            },
            "SQL": {
                "BACKEND": "SQL",
                "CONNECTION" : "mssql://${azurerm_mssql_server.server.administrator_login}:${urlencode(local.db_admin_password)}@${azurerm_mssql_server.server.fully_qualified_domain_name}:1433:${azurerm_mssql_database.db.name}"
            }
        }
        EOT
      }
      env {
        name  = "LC_CTYPE"
        value = "en_US.utf8"
      }
      env {
        name  = "SENZING_SUBCOMMAND"
        value = "mandatory"
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
        name  = "AZURE_ANIMAL"
        value = random_pet.rg_name.id
      }
    }


    container {
      name   = "${random_pet.rg_name.id}-senzingapi-tools"
      image  = var.senzingapi-tools-image
      cpu    = 0.5
      memory = "1Gi"
      command = ["/bin/bash", "-c", var.use_mstools_init_command]

      env {
        name  = "SENZING_ENGINE_CONFIGURATION_JSON"
        value = <<EOT
        {
            "PIPELINE": {
                "CONFIGPATH": "/etc/opt/senzing",
                "LICENSESTRINGBASE64": "{license_string}",
                "RESOURCEPATH": "/opt/senzing/g2/resources",
                "SUPPORTPATH": "/opt/senzing/data"
            },
            "SQL": {
                "BACKEND": "SQL",
                "CONNECTION" : "mssql://${azurerm_mssql_server.server.administrator_login}:${urlencode(local.db_admin_password)}@${azurerm_mssql_server.server.fully_qualified_domain_name}:1433:${azurerm_mssql_database.db.name}"
            }
        }
        EOT
      }
      env {
        name  = "LC_CTYPE"
        value = "en_US.utf8"
      }
      env {
        name  = "SENZING_SUBCOMMAND"
        value = "mandatory"
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
        name  = "AZURE_ANIMAL"
        value = random_pet.rg_name.id
      }
    }

    container {
      name   = "${random_pet.rg_name.id}-senzing-producer"
      image  = var.senzing-producer-image
      cpu    = 2
      memory = "4Gi"
      # command = ["/bin/bash", "-c", var.db_init_command]

      env {
        name  = "SENZING_ENGINE_CONFIGURATION_JSON"
        value = <<EOT
        {
            "PIPELINE": {
                "CONFIGPATH": "/etc/opt/senzing",
                "LICENSESTRINGBASE64": "{license_string}",
                "RESOURCEPATH": "/opt/senzing/g2/resources",
                "SUPPORTPATH": "/opt/senzing/data"
            },
            "SQL": {
                "BACKEND": "SQL",
                "CONNECTION" : "mssql://${azurerm_mssql_server.server.administrator_login}:${urlencode(local.db_admin_password)}@${azurerm_mssql_server.server.fully_qualified_domain_name}:1433:${azurerm_mssql_database.db.name}"
            }
        }
        EOT
      }
      env {
        name  = "LC_CTYPE"
        value = "en_US.utf8"
      }
      env {
        name  = "AZURE_ANIMAL"
        value = random_pet.rg_name.id
      }
      env {
        name = "SENZING_DEFAULT_DATA_SOURCE"
        value = "TEST"
      }
      env {
        name = "SENZING_DEFAULT_ENTITY_TYPE"
        value = "GENERIC"
      }
      env {
        name = "SENZING_INPUT_URL"
        value = "https://public-read-access.s3.amazonaws.com/TestDataSets/test-dataset-100m.json.gz"
      }
      env {
        name = "SENZING_MONITORING_PERIOD_IN_SECONDS"
        value = "60"
      }
      env {
        name = "SENZING_READ_QUEUE_MAXSIZE"
        value = "200"
      }
      env {
        name = "SENZING_RECORD_MAX"
        value = var.number_of_records
      }
      env {
        name = "SENZING_RECORD_MIN"
        value = "0"
      }
      env {
        name = "SENZING_RECORD_MONITOR"
        value = "100000"
      }
      env {
        name = "SENZING_RECORDS_PER_MESSAGE"
        value = "1"
      }
      env {
        name = "SENZING_AZURE_QUEUE_CONNECTION_STRING"
        value = azurerm_servicebus_namespace.sz_service_bus.default_primary_connection_string
      }
      env {
        name = "SENZING_AZURE_QUEUE_NAME"
        value = azurerm_servicebus_queue.sz_queue.name
      }
      env {
        name = "SENZING_SUBCOMMAND"
        value = "gzipped-json-to-azure-queue"
      }
      env {
        name = "SENZING_THREADS_PER_PRINT"
        value = "30"
      }

    }
  }
}

