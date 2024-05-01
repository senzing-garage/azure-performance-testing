######################################################
# record producer container instances
resource "azurerm_container_group" "sz_producer_0" {
  name                = "${random_pet.rg_name.id}-continst-0"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_address_type     = "None"
  os_type             = "Linux"
  restart_policy      = "OnFailure"
  depends_on          = [azurerm_servicebus_queue.sz_queue]

  # Senzing Producer, sends data to Azure Queue
  container {
    name   = "${random_pet.rg_name.id}-senzing-producer-0"
    image  = var.senzing_producer_image
    cpu    = 0.5
    memory = "2.0"
    # command = ["/bin/bash", "-c", "while true; do echo grumble $(date); sleep 600;done"]

    environment_variables = {
      "AZURE_ANIMAL"                          = random_pet.rg_name.id
      "LC_CTYPE"                              = "en_US.utf8"
      "SENZING_AZURE_QUEUE_CONNECTION_STRING" = azurerm_servicebus_namespace.sz_service_bus.default_primary_connection_string
      "SENZING_AZURE_QUEUE_NAME"              = azurerm_servicebus_queue.sz_queue.name
      "SENZING_DEFAULT_DATA_SOURCE"           = "TEST"
      "SENZING_DEFAULT_ENTITY_TYPE"           = "GENERIC"
      "SENZING_INPUT_URL"                     = var.test_data_url
      "SENZING_MONITORING_PERIOD_IN_SECONDS"  = "60"
      "SENZING_READ_QUEUE_MAXSIZE"            = "200"
      "SENZING_RECORD_MAX"                    = var.number_of_records / 8
      "SENZING_RECORD_MIN"                    = "0"
      "SENZING_RECORD_MONITOR"                = "100000"
      "SENZING_RECORDS_PER_MESSAGE"           = "10"
      "SENZING_SUBCOMMAND"                    = "gzipped-json-to-azure-queue"
      "SENZING_THREADS_PER_PRINT"             = "30"
    }
  }
  container {
    name   = "${random_pet.rg_name.id}-senzing-producer-1"
    image  = var.senzing_producer_image
    cpu    = 0.5
    memory = "2.0"
    # command = ["/bin/bash", "-c", "while true; do echo grumble $(date); sleep 600;done"]

    environment_variables = {
      "AZURE_ANIMAL"                          = random_pet.rg_name.id
      "LC_CTYPE"                              = "en_US.utf8"
      "SENZING_AZURE_QUEUE_CONNECTION_STRING" = azurerm_servicebus_namespace.sz_service_bus.default_primary_connection_string
      "SENZING_AZURE_QUEUE_NAME"              = azurerm_servicebus_queue.sz_queue.name
      "SENZING_DEFAULT_DATA_SOURCE"           = "TEST"
      "SENZING_DEFAULT_ENTITY_TYPE"           = "GENERIC"
      "SENZING_INPUT_URL"                     = var.test_data_url
      "SENZING_MONITORING_PERIOD_IN_SECONDS"  = "60"
      "SENZING_READ_QUEUE_MAXSIZE"            = "200"
      "SENZING_RECORD_MAX"                    = (var.number_of_records / 8) * 2
      "SENZING_RECORD_MIN"                    = (var.number_of_records / 8) + 1
      "SENZING_RECORD_MONITOR"                = "100000"
      "SENZING_RECORDS_PER_MESSAGE"           = "10"
      "SENZING_SUBCOMMAND"                    = "gzipped-json-to-azure-queue"
      "SENZING_THREADS_PER_PRINT"             = "30"
    }
  }
  container {
    name   = "${random_pet.rg_name.id}-senzing-producer-2"
    image  = var.senzing_producer_image
    cpu    = 0.5
    memory = "2.0"
    # command = ["/bin/bash", "-c", "while true; do echo grumble $(date); sleep 600;done"]

    environment_variables = {
      "AZURE_ANIMAL"                          = random_pet.rg_name.id
      "LC_CTYPE"                              = "en_US.utf8"
      "SENZING_AZURE_QUEUE_CONNECTION_STRING" = azurerm_servicebus_namespace.sz_service_bus.default_primary_connection_string
      "SENZING_AZURE_QUEUE_NAME"              = azurerm_servicebus_queue.sz_queue.name
      "SENZING_DEFAULT_DATA_SOURCE"           = "TEST"
      "SENZING_DEFAULT_ENTITY_TYPE"           = "GENERIC"
      "SENZING_INPUT_URL"                     = var.test_data_url
      "SENZING_MONITORING_PERIOD_IN_SECONDS"  = "60"
      "SENZING_READ_QUEUE_MAXSIZE"            = "200"
      "SENZING_RECORD_MAX"                    = (var.number_of_records / 8) * 3
      "SENZING_RECORD_MIN"                    = ((var.number_of_records / 8) * 2) + 1
      "SENZING_RECORD_MONITOR"                = "100000"
      "SENZING_RECORDS_PER_MESSAGE"           = "10"
      "SENZING_SUBCOMMAND"                    = "gzipped-json-to-azure-queue"
      "SENZING_THREADS_PER_PRINT"             = "30"
    }
  }
  container {
    name   = "${random_pet.rg_name.id}-senzing-producer-3"
    image  = var.senzing_producer_image
    cpu    = 0.5
    memory = "2.0"
    # command = ["/bin/bash", "-c", "while true; do echo grumble $(date); sleep 600;done"]

    environment_variables = {
      "AZURE_ANIMAL"                          = random_pet.rg_name.id
      "LC_CTYPE"                              = "en_US.utf8"
      "SENZING_AZURE_QUEUE_CONNECTION_STRING" = azurerm_servicebus_namespace.sz_service_bus.default_primary_connection_string
      "SENZING_AZURE_QUEUE_NAME"              = azurerm_servicebus_queue.sz_queue.name
      "SENZING_DEFAULT_DATA_SOURCE"           = "TEST"
      "SENZING_DEFAULT_ENTITY_TYPE"           = "GENERIC"
      "SENZING_INPUT_URL"                     = var.test_data_url
      "SENZING_MONITORING_PERIOD_IN_SECONDS"  = "60"
      "SENZING_READ_QUEUE_MAXSIZE"            = "200"
      "SENZING_RECORD_MAX"                    = (var.number_of_records / 8) * 4
      "SENZING_RECORD_MIN"                    = ((var.number_of_records / 8) * 3) + 1
      "SENZING_RECORD_MONITOR"                = "100000"
      "SENZING_RECORDS_PER_MESSAGE"           = "10"
      "SENZING_SUBCOMMAND"                    = "gzipped-json-to-azure-queue"
      "SENZING_THREADS_PER_PRINT"             = "30"
    }
  }
}

resource "azurerm_container_group" "sz_producer_1" {
  name                = "${random_pet.rg_name.id}-continst-1"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_address_type     = "None"
  os_type             = "Linux"
  restart_policy      = "OnFailure"
  depends_on          = [azurerm_servicebus_queue.sz_queue]

  # Senzing Producer, sends data to Azure Queue
  container {
    name   = "${random_pet.rg_name.id}-senzing-producer-10"
    image  = var.senzing_producer_image
    cpu    = 0.5
    memory = "2.0"
    # command = ["/bin/bash", "-c", "while true; do echo grumble $(date); sleep 600;done"]

    environment_variables = {
      "AZURE_ANIMAL"                          = random_pet.rg_name.id
      "LC_CTYPE"                              = "en_US.utf8"
      "SENZING_AZURE_QUEUE_CONNECTION_STRING" = azurerm_servicebus_namespace.sz_service_bus.default_primary_connection_string
      "SENZING_AZURE_QUEUE_NAME"              = azurerm_servicebus_queue.sz_queue.name
      "SENZING_DEFAULT_DATA_SOURCE"           = "TEST"
      "SENZING_DEFAULT_ENTITY_TYPE"           = "GENERIC"
      "SENZING_INPUT_URL"                     = var.test_data_url
      "SENZING_MONITORING_PERIOD_IN_SECONDS"  = "60"
      "SENZING_READ_QUEUE_MAXSIZE"            = "200"
      "SENZING_RECORD_MAX"                    = (var.number_of_records / 8) * 5
      "SENZING_RECORD_MIN"                    = ((var.number_of_records / 8) * 4) + 1
      "SENZING_RECORD_MONITOR"                = "100000"
      "SENZING_RECORDS_PER_MESSAGE"           = "10"
      "SENZING_SUBCOMMAND"                    = "gzipped-json-to-azure-queue"
      "SENZING_THREADS_PER_PRINT"             = "30"
    }
  }
  container {
    name   = "${random_pet.rg_name.id}-senzing-producer-11"
    image  = var.senzing_producer_image
    cpu    = 0.5
    memory = "2.0"
    # command = ["/bin/bash", "-c", "while true; do echo grumble $(date); sleep 600;done"]

    environment_variables = {
      "AZURE_ANIMAL"                          = random_pet.rg_name.id
      "LC_CTYPE"                              = "en_US.utf8"
      "SENZING_AZURE_QUEUE_CONNECTION_STRING" = azurerm_servicebus_namespace.sz_service_bus.default_primary_connection_string
      "SENZING_AZURE_QUEUE_NAME"              = azurerm_servicebus_queue.sz_queue.name
      "SENZING_DEFAULT_DATA_SOURCE"           = "TEST"
      "SENZING_DEFAULT_ENTITY_TYPE"           = "GENERIC"
      "SENZING_INPUT_URL"                     = var.test_data_url
      "SENZING_MONITORING_PERIOD_IN_SECONDS"  = "60"
      "SENZING_READ_QUEUE_MAXSIZE"            = "200"
      "SENZING_RECORD_MAX"                    = (var.number_of_records / 8) * 6
      "SENZING_RECORD_MIN"                    = ((var.number_of_records / 8) * 5) + 1
      "SENZING_RECORD_MONITOR"                = "100000"
      "SENZING_RECORDS_PER_MESSAGE"           = "10"
      "SENZING_SUBCOMMAND"                    = "gzipped-json-to-azure-queue"
      "SENZING_THREADS_PER_PRINT"             = "30"
    }
  }
  container {
    name   = "${random_pet.rg_name.id}-senzing-producer-12"
    image  = var.senzing_producer_image
    cpu    = 0.5
    memory = "2.0"
    # command = ["/bin/bash", "-c", "while true; do echo grumble $(date); sleep 600;done"]

    environment_variables = {
      "AZURE_ANIMAL"                          = random_pet.rg_name.id
      "LC_CTYPE"                              = "en_US.utf8"
      "SENZING_AZURE_QUEUE_CONNECTION_STRING" = azurerm_servicebus_namespace.sz_service_bus.default_primary_connection_string
      "SENZING_AZURE_QUEUE_NAME"              = azurerm_servicebus_queue.sz_queue.name
      "SENZING_DEFAULT_DATA_SOURCE"           = "TEST"
      "SENZING_DEFAULT_ENTITY_TYPE"           = "GENERIC"
      "SENZING_INPUT_URL"                     = var.test_data_url
      "SENZING_MONITORING_PERIOD_IN_SECONDS"  = "60"
      "SENZING_READ_QUEUE_MAXSIZE"            = "200"
      "SENZING_RECORD_MAX"                    = (var.number_of_records / 8) * 7
      "SENZING_RECORD_MIN"                    = ((var.number_of_records / 8) * 6) + 1
      "SENZING_RECORD_MONITOR"                = "100000"
      "SENZING_RECORDS_PER_MESSAGE"           = "10"
      "SENZING_SUBCOMMAND"                    = "gzipped-json-to-azure-queue"
      "SENZING_THREADS_PER_PRINT"             = "30"
    }
  }
  container {
    name   = "${random_pet.rg_name.id}-senzing-producer-13"
    image  = var.senzing_producer_image
    cpu    = 0.5
    memory = "2.0"
    # command = ["/bin/bash", "-c", "while true; do echo grumble $(date); sleep 600;done"]

    environment_variables = {
      "AZURE_ANIMAL"                          = random_pet.rg_name.id
      "LC_CTYPE"                              = "en_US.utf8"
      "SENZING_AZURE_QUEUE_CONNECTION_STRING" = azurerm_servicebus_namespace.sz_service_bus.default_primary_connection_string
      "SENZING_AZURE_QUEUE_NAME"              = azurerm_servicebus_queue.sz_queue.name
      "SENZING_DEFAULT_DATA_SOURCE"           = "TEST"
      "SENZING_DEFAULT_ENTITY_TYPE"           = "GENERIC"
      "SENZING_INPUT_URL"                     = var.test_data_url
      "SENZING_MONITORING_PERIOD_IN_SECONDS"  = "60"
      "SENZING_READ_QUEUE_MAXSIZE"            = "200"
      "SENZING_RECORD_MAX"                    = var.number_of_records
      "SENZING_RECORD_MIN"                    = ((var.number_of_records / 8) * 7) + 1
      "SENZING_RECORD_MONITOR"                = "100000"
      "SENZING_RECORDS_PER_MESSAGE"           = "10"
      "SENZING_SUBCOMMAND"                    = "gzipped-json-to-azure-queue"
      "SENZING_THREADS_PER_PRINT"             = "30"
    }
  }
}

