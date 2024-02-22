terraform {
  required_version = "~> 1.6"
  required_providers {
    keepass = {
      source = "iSchluff/keepass"
      version = "~> 0"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~>1.5"
    }
    azurerm = {
      source = "hashicorp/azurerm"
      version = "~> 2"
    }
  }
}

provider "keepass" {
  database = "../Cloud Tokens.kdbx"
  password = var.keepass_database_password
}

provider "azurerm" {
  features {}
  subscription_id   = data.keepass_entry.azure_subscription_id.password
  tenant_id         = data.keepass_entry.azure_tenant_id.password
  client_id         = data.keepass_entry.azure_client_id.password
  client_secret     = data.keepass_entry.azure_client_secret.password
}
