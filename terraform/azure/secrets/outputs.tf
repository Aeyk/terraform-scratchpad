output "database_password" {
    value = var.keepass_database_password
}

output "digitalocean_token" {
   value = data.keepass_entry.digitalocean_token.password
}

output "ssh_authorized_keys" {
    value = "${data.keepass_entry.phone_public_ssh_key_contents.attributes.public_key}\n${file(var.public_ssh_key)}${file(var.work_public_ssh_key)}"
}

output "azure_subscription_id" {
    value = data.keepass_entry.azure_subscription_id.password
}

output "azure_tenant_id" {
    value = data.keepass_entry.azure_tenant_id.password
}

output "azure_client_id" {
    value = data.keepass_entry.azure_client_id.password
}

output "azure_client_secret" {
    value = data.keepass_entry.azure_client_secret.password
}

output "home_ssh_key" {
  value = file(var.public_ssh_key)
}

# resource "azurerm_ssh_public_key" "phone_ssh_key" {
#   name                = "phone_ssh_key"
#   resource_group_name = "azure_k8s_eastus2"
#   location            = "eastus"
#   public_key          = data.keepass_entry.phone_public_ssh_key_contents.attributes.public_key
# }

resource "azurerm_ssh_public_key" "home_ssh_key" {
  name                = "home_ssh_key"
  resource_group_name = "azure_k8s_eastus2"
  location            = "eastus2"
  public_key          = file(var.public_ssh_key)
}

resource "azurerm_ssh_public_key" "work_ssh_key" {
  name                = "work_ssh_key"
  resource_group_name = "azure_k8s_eastus2"
  location            = "eastus2"
  public_key          = file(var.work_public_ssh_key)
}