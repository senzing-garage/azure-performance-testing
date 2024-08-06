terraform {
  required_version = ">=1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  # subscription_id   = "${env.ARM_SUBSCRIPTION_ID}"
  # tenant_id         = "${env.ARM_TENANT_ID}"
  # client_id         = "${env.ARM_CLIENT_ID}"
  # client_secret     = "${env.ARM_CLIENT_SECRET}"
}


