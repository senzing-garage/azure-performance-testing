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

output "ip_address" {
  value = azurerm_container_app.sz_perf_app.outbound_ip_addresses
}

#the dns fqdn of the container group if dns_name_label is set
output "fqdn" {
  value = azurerm_container_app.sz_perf_app.latest_revision_fqdn
}
