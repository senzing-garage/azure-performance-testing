variable "number_of_records" {
  type        = string
  description = "Number of records to put into the queue for processing"
  default     = "25000000"
}

variable "senzingapi_tools_image" {
  type        = string
  description = "Repo for the Senzing API Tools image"
  default     = "public.ecr.aws/senzing/senzingapi-tools:staging"
}

variable "senzing_producer_image" {
  type        = string
  description = "Repo for the Senzing producer image"
  default     = "public.ecr.aws/senzing/stream-producer:1.8.7"
  # default     = "docker.io/senzing/stream-producer:1.8.7"
}

variable "senzing_loader_image" {
  type        = string
  description = "Repo for the Senzing loader image"
  default     = "public.ecr.aws/senzing/senzingapi-runtime:staging"
  # default     = "public.ecr.aws/senzing/stream-loader:staging"
  # default     = "public.ecr.aws/senzing/sz_sqs_consumer:staging"
}

variable "senzing_license_string" {
  type        = string
  description = "License string for Senzing."
}

variable "test_data_url" {
  type        = string
  description = "URL for the test data set."
  default     = "https://public-read-access.s3.amazonaws.com/TestDataSets/test-25m_with-updates_shuf.jsonl.gz"
  # default     = "https://public-read-access.s3.amazonaws.com/TestDataSets/test-dataset-100m.json.gz"
}

variable "database_sku" {
  type        = string
  description = "SKU for the database to use"
  # default     = "S0"
  # default = "S3"
  # default = "HS_Gen5_16"
  default = "HS_Gen5_32"
}
# ref: https://learn.microsoft.com/en-us/azure/azure-sql/database/resource-limits-vcore-single-databases?view=azuresql

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

locals {
  senzing_engine_configuration_json = <<EOT
        {
            "PIPELINE": {
                "CONFIGPATH": "/etc/opt/senzing",
                "LICENSESTRINGBASE64": "${var.senzing_license_string}",
                "RESOURCEPATH": "/opt/senzing/g2/resources",
                "SUPPORTPATH": "/opt/senzing/data"
            },
            "SQL": {
                "BACKEND": "SQL",
                "DEBUGLEVEL": "0",
                "CONNECTION" : "mssql://${azurerm_mssql_server.server.administrator_login}:${urlencode(local.db_admin_password)}@${azurerm_mssql_server.server.fully_qualified_domain_name}:1433:${azurerm_mssql_database.db.name}"
            }
        }
        EOT
}

# DEBUGLEVEL: is a bitmask.  1 means PERF, 2 means SQL, and 3 means both.
#   it only works when vebose-logging is also on.  How do we turn on verbose logging?

variable "use_mstools_init_command" {
  type        = string
  description = "Command to install drivers in order to use Senzing."
  default     = <<EOT
      wget -qO - https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.gpg
      wget -qO - https://packages.microsoft.com/config/debian/11/prod.list > /etc/apt/sources.list.d/mssql-release.list
      apt-get update
      ACCEPT_EULA=Y apt-get -y install msodbcsql18 mssql-tools18
      echo 'export PATH="$PATH:/opt/mssql-tools18/bin"' >> ~/.bashrc
      source ~/.bashrc
      while true; do echo grumble $(date); sleep 600;done
  EOT
}

variable "db_init_command" {
  type        = string
  description = "Command to initialize the database."
  default     = <<EOT
      wget -qO - https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.gpg
      wget -qO - https://packages.microsoft.com/config/debian/11/prod.list > /etc/apt/sources.list.d/mssql-release.list
      apt-get update
      ACCEPT_EULA=Y apt-get -y install msodbcsql18 mssql-tools18
      echo 'export PATH="$PATH:/opt/mssql-tools18/bin"' >> ~/.bashrc
      source ~/.bashrc
      export TOOLS_VERSION=$(apt policy senzingapi-tools|grep Installed |cut -d ":" -f 2| awk '{$1=$1};1')
      apt-get -y install senzingapi-setup=$TOOLS_VERSION
      sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -i /opt/senzing/g2/resources/schema/g2core-schema-mssql-create.sql -o /tmp/schema.out
      echo "ALTER DATABASE G2 SET DELAYED_DURABILITY = Forced;" > /tmp/alterdb.sql
      echo "ALTER DATABASE G2 SET AUTO_UPDATE_STATISTICS_ASYNC ON;" >> /tmp/alterdb.sql
      echo "ALTER DATABASE G2 SET AUTO_CREATE_STATISTICS ON;" >> /tmp/alterdb.sql
      echo "ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 1;" >> /tmp/alterdb.sql
      sqlcmd -S $AZURE_ANIMAL-mssql-server.database.windows.net -d G2 -U senzing -P "$SENZING_DB_PWD" -i /tmp/alterdb.sql -o /tmp/alterdb.out
      echo "addDataSource CUSTOMERS" > /tmp/add.sz
      echo "addDataSource REFERENCE" >> /tmp/add.sz
      echo "addDataSource WATCHLIST" >> /tmp/add.sz
      echo "save" >> /tmp/add.sz
      G2ConfigTool.py -f /tmp/add.sz
  EOT
}

# while true; do echo grumble $(date); sleep 600;done
