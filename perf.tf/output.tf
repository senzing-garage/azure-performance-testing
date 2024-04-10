output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "sql_server_name" {
  value = azurerm_mssql_server.server.name
}

output "sql_database_name" {
  value = var.sql_db_name
}

output "db_admin_password" {
  sensitive = true
  value     = local.db_admin_password
}

output "queue_name" {
  value = azurerm_servicebus_queue.sz_queue.name
}

output "queue_connection_string" {
  sensitive = true
  value = azurerm_servicebus_namespace.sz_service_bus.default_primary_connection_string
}
