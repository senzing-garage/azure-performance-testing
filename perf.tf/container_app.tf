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

  # registry {
  #   server = "docker.io"
  # }

  # ingress {
  #   allow_insecure_connections = false
  #   external_enabled           = true
  #   target_port                = 80
  #   traffic_weight {
  #     percentage = 100
  #   }

  # }

  template {
    # init_container {
    #   name  = "${random_pet.rg_name.id}-init-database"
    #   image = "docker.io/senzing/init-database:0.5.2"
    #   cpu   = 0.25
    #   env {
    #     name  = "SENZING_TOOLS_ENGINE_CONFIGURATION_JSON"
    #     value = <<EOT
    #     {
    #         "PIPELINE": {
    #             "CONFIGPATH": "/etc/opt/senzing",
    #             "LICENSESTRINGBASE64": "{license_string}",
    #             "RESOURCEPATH": "/opt/senzing/g2/resources",
    #             "SUPPORTPATH": "/opt/senzing/data"
    #         },
    #         "SQL": {
    #             "BACKEND": "SQL",
    #             "CONNECTION" : "mssql://${azurerm_mssql_server.server.administrator_login}:${local.db_admin_password}@${azurerm_mssql_server.server.fully_qualified_domain_name}:1433:${azurerm_mssql_database.db.name}/?driver=mssqldriver"
    #         }
    #     }
    #   EOT
    #   }
    #   env {
    #     name  = "LC_CTYPE"
    #     value = "en_US.utf8"
    #   }
    #   env {
    #     name  = "SENZING_SUBCOMMAND"
    #     value = "mandatory"
    #   }
    #   env {
    #     name  = "SENZING_DEBUG"
    #     value = "False"
    #   }
    # }

    container {
      name   = "${random_pet.rg_name.id}-senzingapi-tools"
      image  = "docker.io/senzing/senzingapi-tools:3.9.0"
      cpu    = 0.5
      memory = "1Gi"
      command = ["/bin/bash", "-c", "while true; do echo hello $(date); sleep 1000;done"]
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
                "CONNECTION" : "mssql://${azurerm_mssql_server.server.administrator_login}:${local.db_admin_password}@${azurerm_mssql_server.server.fully_qualified_domain_name}:1433:${azurerm_mssql_database.db.name}/?driver=mssqldriver"
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
    }


## REF: https://learn.microsoft.com/en-us/sql/connect/odbc/linux-mac/installing-the-microsoft-odbc-driver-for-sql-server?view=sql-server-ver16&tabs=debian18-install%2Cdebian17-install%2Cdebian8-install%2Credhat7-13-install%2Crhel7-offline
#  /bin/bash
#  wget -qO - https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.gpg \
#  && wget -qO - https://packages.microsoft.com/config/debian/11/prod.list > /etc/apt/sources.list.d/mssql-release.list \
#  && apt-get update \
#  && ACCEPT_EULA=Y apt-get -y install msodbcsql17 \
#  && ACCEPT_EULA=Y apt-get -y install mssql-tools
#  echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc
#  source ~/.bashrc

    # container {
    #   name   = "${random_pet.rg_name.id}-debian"
    #   image  = "docker.io/debian:latest"
    #   cpu    = 0.5
    #   memory = "1Gi"
    #   env {
    #     name  = "SENZING_TOOLS_ENGINE_CONFIGURATION_JSON"
    #     value = <<EOT
    #     {
    #         "PIPELINE": {
    #             "CONFIGPATH": "/etc/opt/senzing",
    #             "LICENSESTRINGBASE64": "{license_string}",
    #             "RESOURCEPATH": "/opt/senzing/g2/resources",
    #             "SUPPORTPATH": "/opt/senzing/data"
    #         },
    #         "SQL": {
    #             "BACKEND": "SQL",
    #             "CONNECTION" : "mssql://${azurerm_mssql_server.server.administrator_login}:${local.db_admin_password}@${azurerm_mssql_server.server.fully_qualified_domain_name}:1433/${azurerm_mssql_database.db.name}"
    #         }
    #     }
    #   EOT
    #   }
    #   env {
    #     name  = "LC_CTYPE"
    #     value = "en_US.utf8"
    #   }
    #   env {
    #     name  = "SENZING_SUBCOMMAND"
    #     value = "mandatory"
    #   }
    #   env {
    #     name  = "SENZING_DEBUG"
    #     value = "False"
    #   }
    # }
  }
}

