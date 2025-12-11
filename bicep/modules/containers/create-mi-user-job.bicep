// =============================================================================
// Create Managed Identity User Job Module
// =============================================================================
// Creates Container Apps Job that creates the Managed Identity database user
// IMPORTANT: Uses PASSWORD authentication to CREATE the MI user
// After this job runs, MI authentication will be available
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

@description('Managed Identity name to create as database user')
param managedIdentityName string

// =============================================================================
// Container Apps Job - Create MI User
// =============================================================================

resource createMiUserJob 'Microsoft.App/jobs@2023-05-01' = {
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
          name: 'create-mi-user'
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
            {
              name: 'MI_NAME'
              value: managedIdentityName
            }
          ]
          command: [
            '/bin/bash'
            '-c'
            '''
            echo "Creating Managed Identity database user: $MI_NAME"

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

            # Create the managed identity user from Azure AD
            # In Azure SQL, external users are created with CREATE USER ... FROM EXTERNAL PROVIDER
            /opt/mssql-tools/bin/sqlcmd -S "$SQL_HOST,$SQL_PORT" -U "$SQL_USER" -P "$SQL_PASSWORD" -d "$SQL_DATABASE" -Q "
            IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '$MI_NAME')
            BEGIN
                CREATE USER [$MI_NAME] FROM EXTERNAL PROVIDER;
                PRINT 'Created user $MI_NAME';
            END
            ELSE
            BEGIN
                PRINT 'User $MI_NAME already exists';
            END
            "

            # Grant permissions
            /opt/mssql-tools/bin/sqlcmd -S "$SQL_HOST,$SQL_PORT" -U "$SQL_USER" -P "$SQL_PASSWORD" -d "$SQL_DATABASE" -Q "
            ALTER ROLE db_owner ADD MEMBER [$MI_NAME];
            PRINT 'Granted db_owner role to $MI_NAME';
            "

            echo "Managed Identity user created and granted permissions"
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

output jobId string = createMiUserJob.id
output jobName string = createMiUserJob.name
