variable "resource_group_location" {
  type        = string
  description = "Location for all resources."
  default     = "westus"
}

variable "resource_group_name_prefix" {
  type        = string
  description = "Prefix of the resource group name that's combined with a random ID so name is unique in your Azure subscription."
  default     = "rg"
}

variable "sql_db_name" {
  type        = string
  description = "The name of the SQL Database."
  default     = "G2"
}

variable "db_admin_username" {
  type        = string
  description = "The administrator username of the SQL logical server."
  default     = "senzing"
}

variable "db_admin_password" {
  type        = string
  description = "The administrator password of the SQL logical server."
  sensitive   = true
  default     = null
}