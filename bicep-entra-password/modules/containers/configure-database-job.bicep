// =============================================================================
// Configure Database Job Module
// =============================================================================
// Creates Container Apps Job that configures database performance settings
// Uses SQL PASSWORD authentication (runs before Entra user is created)
// =============================================================================

@description('Name of the job')
param name string

@description('Location for the job')
param location string

@description('Container Apps Environment ID')
param containerAppsEnvId string

@description('Azure SQL server hostname')
param sqlHost string

@description('Azure SQL server port')
param sqlPort int

@description('Azure SQL database name')
param sqlDatabase string

@description('Azure SQL admin username')
param sqlAdminUser string

@description('Azure SQL admin password')
@secure()
param sqlAdminPassword string

// =============================================================================
// Container Apps Job - Configure Database
// =============================================================================

resource configureDatabaseJob 'Microsoft.App/jobs@2023-05-01' = {
  name: name
  location: location
  properties: {
    environmentId: containerAppsEnvId
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 600 // 10 minutes
      replicaRetryLimit: 1
      secrets: [
        {
          name: 'sql-password'
          value: sqlAdminPassword
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'configure-database'
          image: 'mcr.microsoft.com/mssql-tools:latest'
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'SQL_HOST'
              value: sqlHost
            }
            {
              name: 'SQL_PORT'
              value: string(sqlPort)
            }
            {
              name: 'SQL_DATABASE'
              value: sqlDatabase
            }
            {
              name: 'SQL_USER'
              value: sqlAdminUser
            }
            {
              name: 'SQL_PASSWORD'
              secretRef: 'sql-password'
            }
          ]
          command: [
            '/bin/bash'
            '-c'
            '''
            echo "Configuring database performance settings..."

            # Wait for database to be ready
            for i in {1..30}; do
              /opt/mssql-tools/bin/sqlcmd -S "$SQL_HOST,$SQL_PORT" -U "$SQL_USER" -P "$SQL_PASSWORD" -d master -Q "SELECT 1" > /dev/null 2>&1
              if [ $? -eq 0 ]; then
                echo "Database is ready"
                break
              fi
              echo "Waiting for SQL Server... (attempt $i/30)"
              sleep 10
            done

            # Configure DELAYED_DURABILITY for better write performance
            echo "Setting DELAYED_DURABILITY = Forced..."
            /opt/mssql-tools/bin/sqlcmd -S "$SQL_HOST,$SQL_PORT" -U "$SQL_USER" -P "$SQL_PASSWORD" -d "$SQL_DATABASE" -Q "
            ALTER DATABASE CURRENT SET DELAYED_DURABILITY = Forced;
            PRINT 'DELAYED_DURABILITY set to Forced';
            "

            # Enable auto-create statistics
            echo "Setting AUTO_CREATE_STATISTICS ON..."
            /opt/mssql-tools/bin/sqlcmd -S "$SQL_HOST,$SQL_PORT" -U "$SQL_USER" -P "$SQL_PASSWORD" -d "$SQL_DATABASE" -Q "
            ALTER DATABASE CURRENT SET AUTO_CREATE_STATISTICS ON;
            PRINT 'AUTO_CREATE_STATISTICS enabled';
            "

            # Enable async statistics updates
            echo "Setting AUTO_UPDATE_STATISTICS_ASYNC ON..."
            /opt/mssql-tools/bin/sqlcmd -S "$SQL_HOST,$SQL_PORT" -U "$SQL_USER" -P "$SQL_PASSWORD" -d "$SQL_DATABASE" -Q "
            ALTER DATABASE CURRENT SET AUTO_UPDATE_STATISTICS_ASYNC ON;
            PRINT 'AUTO_UPDATE_STATISTICS_ASYNC enabled';
            "

            echo "Database configuration complete"
            '''
          ]
        }
      ]
    }
  }
}

// =============================================================================
// Outputs
// =============================================================================

output jobId string = configureDatabaseJob.id
output jobName string = configureDatabaseJob.name
