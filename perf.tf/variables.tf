variable "prefix" {
  type        = string
  description = "Prefix for all resources."
  default     = "sz"
}

variable "resource_group_location" {
  type        = string
  description = "Location for all resources."
  default     = "westus"
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

variable "db_init_command" {
  type        = string
  description = "Command to initialize the database."
  default     = <<EOT
      wget -qO - https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.gpg
      wget -qO - https://packages.microsoft.com/config/debian/11/prod.list > /etc/apt/sources.list.d/mssql-release.list
      apt-get update
      ACCEPT_EULA=Y apt-get -y install msodbcsql17 mssql-tools
      echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc
      source ~/.bashrc
      wget -qO - https://raw.githubusercontent.com/senzing-garage/init-database/main/rootfs/opt/senzing/g2/resources/schema/g2core-schema-mssql-create.sql > /tmp/g2core-schema-mssql-create.sql
      sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -i /tmp/g2core-schema-mssql-create.sql -o /tmp/schema.out
      echo "addDataSource CUSTOMERS" > /tmp/add.sz
      echo "addDataSource REFERENCE" >> /tmp/add.sz
      echo "addDataSource WATCHLIST" >> /tmp/add.sz
      echo "save" >> /tmp/add.sz
      G2ConfigTool.py -f /tmp/add.sz
      while true; do echo grumble $(date); sleep 600;done
  EOT
}

