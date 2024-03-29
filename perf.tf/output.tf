output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "sql_server_name" {
  value = azurerm_mssql_server.server.name
}


output "db_admin_password" {
  sensitive = true
  value     = local.db_admin_password
}