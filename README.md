# azure-performance-testing

[Azure portal](http://portal.azure.com/)

## Infrastructure automation tools

- Azure overview: https://learn.microsoft.com/en-us/azure/virtual-machines/infrastructure-automation

- Bicep: https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/
- Terraform: https://learn.microsoft.com/en-us/azure/developer/terraform/
- ARM Templates: JSON based, easier to use Bicep which "compiles" down to this.
- Docker compose:
    - https://learn.microsoft.com/en-us/azure/container-instances/tutorial-docker-compose
    - https://docs.docker.com/compose/compose-file/05-services/#scale

## az - Azure CLI

- https://learn.microsoft.com/en-us/cli/azure/install-azure-cli

Login to Azure and set up credentials for terraform:

```
$ az login
A web browser has been opened at https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize. Please continue the login in the web browser. If no web browser is available or if the web browser fails to open, use device code flow with `az login --use-device-code`.
[
  {
    "cloudName": "AzureCloud",
    "homeTenantId": "<tenantId>",
    "id": "<subscriptionId>",
    "isDefault": true,
    "managedByTenants": [],
    "name": "<subscription name>",
    "state": "Enabled",
    "tenantId": "<tenantId>",
    "user": {
      "name": "<email address>",
      "type": "user"
    }
  }
]

$ az account set --subscription "<subscriptionId>"
$ az ad sp create-for-rbac --role="Contributor" --scopes="/subscriptions/<subscriptionId>"
Creating 'Contributor' role assignment under scope '/subscriptions/<subscriptionId>'
The output includes credentials that you must protect. Be sure that you do not include these credentials in your code or check the credentials into your source control. For more information, see https://aka.ms/azadsp-cli
{
  "appId": "<appId>",
  "displayName": "azure-cli-2024-03-29-15-15-53",
  "password": "<password>",
  "tenant": "<tenantId>"
}

$ export ARM_CLIENT_ID="<appId>"
$ export ARM_CLIENT_SECRET="<password>"
$ export ARM_SUBSCRIPTION_ID="<subscriptionId>"
$ export ARM_TENANT_ID="<tenantId>"


# check expiration of login
az account get-access-token
```

## Terraform

To create the resources, in the `perf.tf` directory:

```
terraform init -upgrade
terraform plan -out main.tfplan
terraform apply main.tfplan

terraform output -json | jq -r ".db_admin_password.value"
```

Other terraform things to play with:

```
resource_group_name=$(terraform output -raw resource_group_name)
az group show --name $resource_group_name

terraform show -json main.tfplan

```

To destroy the resources, in the `perf.tf` directory:

```
terraform plan -destroy -out main.destroy.tfplan
terraform apply main.destroy.tfplan
```

### NOTES:

#### references:

- terraform on azure: https://learn.microsoft.com/en-us/azure/developer/terraform/
- resource group creation: https://learn.microsoft.com/en-us/azure/developer/terraform/create-resource-group?tabs=azure-cli
    - left panel lists other resources and howtos of interest

#### environment variables:

Terraform can directly access environment variables that are named using the pattern TF_VAR_, for example TF_VAR_foo=bar will provide the value bar to the variable declared using variable "foo" {}

Ref. https://support.hashicorp.com/hc/en-us/articles/4547786359571-Reading-and-using-environment-variables-in-Terraform-runs

## sqlcmd

- https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-setup-tools?view=sql-server-ver16&tabs=redhat-install
- https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-utility?view=sql-server-ver16&tabs=go%2Cmac&pivots=cs1-bash

### Install using brew:

- https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-setup-tools?view=sql-server-ver16&tabs=redhat-install

```
brew tap microsoft/mssql-release https://github.com/Microsoft/homebrew-mssql-release
brew update
brew install mssql-tools18
```

### Using sqlcmd:

- https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-utility?view=sql-server-ver16&tabs=go%2Cwindows&pivots=cs1-bash

```
export SQLCMDPASSWORD=$(terraform output -json | jq -r ".db_admin_password.value")
sqlcmd -Ssenzing-sql-server.database.windows.net -dG2 -Usenzing
1> select @@version
2> go
```

Note: must always use "go" to execute the sql command. Use "exit" to quit sqlcmd.

