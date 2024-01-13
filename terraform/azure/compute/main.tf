terraform {
  required_version = "~> 1.6"
  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~>1.5"
    }
    azurerm = {
      source = "hashicorp/azurerm"
      version = "~> 2"
    }
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id   = module.secrets.azure_subscription_id
  tenant_id         = module.secrets.azure_tenant_id
  client_id         = module.secrets.azure_client_id
  client_secret     = module.secrets.azure_client_secret
}

module "secrets" {
  source = "../secrets"
  keepass_database_password = var.keepass_database_password
}

module "network" {
  source = "../network"
  keepass_database_password = var.keepass_database_password
}

resource "azurerm_storage_account" "main" {
  name                     = "hnrwdw5q3qsay"
  location                 = "eastus2"
  resource_group_name      = "azure_resource_group"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_linux_virtual_machine" "main" {
  computer_name         = "azure-amd64-ubuntu-usirc"
  name                  = "azure_amd64_ubuntu_usirc"
  location              = "eastus2"
  resource_group_name   = "azure_resource_group"
  network_interface_ids = [module.network.azure_vnic.id]
  size                  = "Standard_D4s_v3"

  os_disk {
    name                 = "azure_amd64_virtual_machine-boot_disk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  admin_username = "ubuntu"
  admin_ssh_key {
    username   = "ubuntu"
    public_key = module.secrets.home_ssh_key
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.main.primary_blob_endpoint
  }
}