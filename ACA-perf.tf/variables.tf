variable "number_of_records" {
  type        = string
  description = "Number of records to put into the queue for processing"
  default     = "1000000"
}

variable "senzingapi-tools-image" {
  type        = string
  description = "Repo for the Senzing API Tools image"
  default     = "public.ecr.aws/senzing/senzingapi-tools:staging"
}

variable "senzing-producer-image" {
  type        = string
  description = "Repo for the Senzing producer image"
  default     = "docker.io/senzing/stream-producer:1.8.7"
}

variable "senzing-loader-image" {
  type        = string
  description = "Repo for the Senzing loader image"
  default     = "public.ecr.aws/senzing/senzingapi-runtime:staging"
  # default     = "public.ecr.aws/senzing/stream-loader:staging"
  # default     = "public.ecr.aws/senzing/sz_sqs_consumer:staging"
}

variable "test_data_url" {
  type        = string
  description = "URL for the test data set."
  default     = "https://public-read-access.s3.amazonaws.com/TestDataSets/test-dataset-100m.json.gz"
}

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
      echo "addDataSource CUSTOMERS" > /tmp/add.sz
      echo "addDataSource REFERENCE" >> /tmp/add.sz
      echo "addDataSource WATCHLIST" >> /tmp/add.sz
      echo "save" >> /tmp/add.sz
      G2ConfigTool.py -f /tmp/add.sz
  EOT
}

variable "init_loader_command" {
  type        = string
  description = "Command to install drivers in order to use Senzing."
  default     = <<EOT
      wget -qO - https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.gpg
      wget -qO - https://packages.microsoft.com/config/debian/11/prod.list > /etc/apt/sources.list.d/mssql-release.list
      apt-get update
      ACCEPT_EULA=Y apt-get -y install \
        libaio1 libodbc1 libxml2 \
        msodbcsql18 mssql-tools18 \
        python3 python3-dev python3-pip python3-venv unixodbc
      python3 -m venv /app/venv
      export PATH="/app/venv/bin:$PATH"
      wget -qO - https://raw.githubusercontent.com/senzing-garage/stream-loader/main/requirements.txt > /app/requirements.txt
      cd /app
      pip3 install --upgrade pip
      pip3 install -r requirements.txt
      wget -qO - https://raw.githubusercontent.com/Senzing/governor-postgresql-transaction-id/main/senzing_governor.py > /opt/senzing/g2/sdk/python/senzing_governor.py
      wget -qO - https://raw.githubusercontent.com/senzing-garage/stream-loader/main/rootfs/app/container-test.sh > /app/container-test.sh
      wget -qO - https://raw.githubusercontent.com/senzing-garage/stream-loader/main/rootfs/app/healthcheck.sh > /app/healthcheck.sh
      wget -qO - https://raw.githubusercontent.com/senzing-garage/stream-loader/main/stream-loader.py > /app/stream-loader.py
      chmod +x /app/container-test.sh
      chmod +x /app/healthcheck.sh
      chmod +x /app/stream-loader.py
      echo 'export VIRTUAL_ENV=/app/venv' >> ~/.bashrc
      echo 'export PATH="/app/venv/bin:$PATH:/opt/mssql-tools18/bin:/opt/senzing/g2/python:/opt/IBM/db2/clidriver/adm:/opt/IBM/db2/clidriver/bin"' >> ~/.bashrc
      echo 'export PYTHONPATH="$PYTHONPATH:/opt/senzing/g2/sdk/python:/app"' >> ~/.bashrc
      echo 'export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/opt/senzing/g2/lib:/opt/senzing/g2/lib/debian:/opt/IBM/db2/clidriver/lib"' >> ~/.bashrc
      echo 'export SENZING_DOCKER_LAUNCHED=true' >> ~/.bashrc
      echo 'export PYTHONUNBUFFERED=1' >> ~/.bashrc
      source ~/.bashrc
      /app/stream-loader.py
  EOT
}

# while true; do echo grumble $(date); sleep 600;done

# HEALTHCHECK CMD ["/app/healthcheck.sh"]

# RUN apt update \
#   && apt -y install \
#   librdkafka-dev \
#   postgresql-client \

# WORKDIR /app
# ENTRYPOINT ["/app/stream-loader.py"]


variable "init_sz_consumer_command" {
  type        = string
  description = "Command to install drivers in order to use Senzing."
  default     = <<EOT
      wget -qO - https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.gpg
      wget -qO - https://packages.microsoft.com/config/debian/11/prod.list > /etc/apt/sources.list.d/mssql-release.list
      apt-get update
      apt-get -y install python3 python3-pip python3-boto3 python3-psycopg2
      python3 -mpip install orjson
      apt-get -y remove build-essential python3-pip
      apt-get -y autoremove
      apt-get -y clean
      mkdir /app
      wget -qO - https://raw.githubusercontent.com/brianmacy/sz_sqs_consumer/main/sz_sqs_consumer.py > /app/sz_sqs_consumer.py
      wget -qO - https://raw.githubusercontent.com/Senzing/governor-postgresql-transaction-id/main/senzing_governor.py > /app/senzing_governor.py
      ACCEPT_EULA=Y apt-get -y install msodbcsql18 mssql-tools18
      echo 'export PATH="$PATH:/opt/mssql-tools18/bin"' >> ~/.bashrc
      echo 'export PYTHONPATH="$PYTHONPATH:/opt/senzing/g2/sdk/python:/app"' >> ~/.bashrc
      source ~/.bashrc
      while true; do echo grumble $(date); sleep 600;done
  EOT
}

# while true; do echo grumble $(date); sleep 600;done
