# azure-performance-testing

[Azure portal](http://portal.azure.com/)

## Infrastructure automation tools

- Azure overview: https://learn.microsoft.com/en-us/azure/virtual-machines/infrastructure-automation

- Bicep: https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/
- Terraform: https://learn.microsoft.com/en-us/azure/developer/terraform/
- ARM Templates: JSON based, easier to use Bicep which "compiles" down to this.

## az - Azure CLI

- https://learn.microsoft.com/en-us/cli/azure/install-azure-cli

## Terraform

To create the resources, in the `perf.tf` directory:

```
terraform init -upgrade
terraform plan -out main.tfplan
terraform apply main.tfplan
```

To destroy the resources, in the `perf.tf` directory:

```
terraform plan -destroy -out main.destroy.tfplan
terraform apply main.destroy.tfplan
```

## sqlcmd

- https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-setup-tools?view=sql-server-ver16&tabs=redhat-install

Install using brew:

```
brew tap microsoft/mssql-release https://github.com/Microsoft/homebrew-mssql-release
brew update
brew install mssql-tools18
```