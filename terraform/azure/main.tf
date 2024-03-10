terraform {
  required_version = "~> 1.6"
  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~>1.5"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2"
    }
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2"
    }
    keepass = {
      source  = "iSchluff/keepass"
      version = "~> 0"
    }
  }
}

provider "azurerm" {
  features {}
  skip_provider_registration = true
  subscription_id            = module.secrets.azure_subscription_id
  tenant_id                  = module.secrets.azure_tenant_id
  client_id                  = module.secrets.azure_client_id
  client_secret              = module.secrets.azure_client_secret
}

provider "keepass" {
  database = "~/Documents/Cloud Tokens.kdbx"
  password = var.keepass_database_password
}

provider "digitalocean" {
  token = module.secrets.digitalocean_token
}

module "secrets" {
  source                    = "./secrets"
  keepass_database_password = var.keepass_database_password
}

module "network" {
  keepass_database_password = var.keepass_database_password
  source                    = "./network"
}

module "compute" {
  keepass_database_password = var.keepass_database_password
  source                    = "./compute"
}

resource "azurerm_resource_group" "main" {
  location = "eastus2"
  name     = "azure_resource_group"
  # lifecycle {
  #   prevent_destroy = true
  # }
}