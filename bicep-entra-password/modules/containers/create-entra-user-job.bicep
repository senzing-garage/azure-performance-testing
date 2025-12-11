// =============================================================================
// Create Entra ID User Job Module
// =============================================================================
// Creates Container Apps Job that creates the Entra ID database user
// IMPORTANT: Uses SQL PASSWORD authentication to CREATE the Entra user
// After this job runs, Entra ID Password authentication will be available
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

@description('Entra ID user email to create as database user')
param entraUserEmail string

// =============================================================================
// Container Apps Job - Create Entra ID User
// =============================================================================

resource createEntraUserJob 'Microsoft.App/jobs@2023-05-01' = {
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
          name: 'create-entra-user'
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
              name: 'ENTRA_USER_EMAIL'
              value: entraUserEmail
            }
          ]
          command: [
            '/bin/bash'
            '-c'
            '''
            echo "Creating Entra ID database user: $ENTRA_USER_EMAIL"

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

            # Create the Entra ID user from Azure AD
            # In Azure SQL, external users (Entra ID) are created with CREATE USER ... FROM EXTERNAL PROVIDER
            # The email address becomes the user name
            /opt/mssql-tools/bin/sqlcmd -S "$SQL_HOST,$SQL_PORT" -U "$SQL_USER" -P "$SQL_PASSWORD" -d "$SQL_DATABASE" -Q "
            IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '$ENTRA_USER_EMAIL')
            BEGIN
                CREATE USER [$ENTRA_USER_EMAIL] FROM EXTERNAL PROVIDER;
                PRINT 'Created user $ENTRA_USER_EMAIL';
            END
            ELSE
            BEGIN
                PRINT 'User $ENTRA_USER_EMAIL already exists';
            END
            "

            # Grant permissions
            /opt/mssql-tools/bin/sqlcmd -S "$SQL_HOST,$SQL_PORT" -U "$SQL_USER" -P "$SQL_PASSWORD" -d "$SQL_DATABASE" -Q "
            ALTER ROLE db_owner ADD MEMBER [$ENTRA_USER_EMAIL];
            PRINT 'Granted db_owner role to $ENTRA_USER_EMAIL';
            "

            echo "Entra ID user created and granted permissions"
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

output jobId string = createEntraUserJob.id
output jobName string = createEntraUserJob.name
