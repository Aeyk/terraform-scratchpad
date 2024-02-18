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

resource "azurerm_virtual_network" "main" {
  name                = "azure_vnet"
  address_space       = ["10.0.0.0/16"]
  location            = "eastus2"
  resource_group_name = "azure_k8s_eastus2"
}

resource "azurerm_subnet" "main" {
  name                 = "azure_private_subnet"
  resource_group_name  = "azure_k8s_eastus2"
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.0.0/24"]
}

resource "azurerm_public_ip" "main" {
  name                = "azure_public_ip"
  location            = "eastus2"
  resource_group_name = "azure_k8s_eastus2"
  allocation_method   = "Dynamic"
}

resource "azurerm_network_security_group" "azure_inbound_ssh_nsg" {
  name                = "azure_network_security_group"
  location            = "eastus2"
  resource_group_name = "azure_k8s_eastus2"

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "main" {
  name                = "azure_vnic"
  location            = "eastus2"
  resource_group_name = "azure_k8s_eastus2"

  ip_configuration {
    name                          = "azure_vnic_configuration"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}