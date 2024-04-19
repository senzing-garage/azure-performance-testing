
output "AZURE_ANIMAL" {
  value = random_pet.rg_name.id
}

output "db_admin_password" {
  sensitive = true
  value     = local.db_admin_password
}


output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "sql_server_name" {
  value = azurerm_mssql_server.server.name
}

output "sql_database_name" {
  value = var.sql_db_name
}

output "SENZING_AZURE_QUEUE_CONNECTION_STRING" {
  sensitive = true
  value     = azurerm_servicebus_namespace.sz_service_bus.default_primary_connection_string
}

output "SENZING_AZURE_QUEUE_NAME" {
  value = azurerm_servicebus_queue.sz_queue.name
}

output "SENZING_ENGINE_CONFIGURATION_JSON" {
  sensitive = true
  value     = local.senzing_engine_configuration_json
}
resource "local_file" "kubeconfig" {
  depends_on = [azurerm_kubernetes_cluster.sz_perf_cluster]
  filename   = "kubeconfig"
  content    = azurerm_kubernetes_cluster.sz_perf_cluster.kube_config_raw
}
