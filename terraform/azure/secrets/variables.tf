variable "private_ssh_key" {
  default = "/home/malik/.ssh/id_rsa"
}

data "keepass_entry" "phone_public_ssh_key_contents" {
  path = "Root/Phone Key"
}

variable "public_ssh_key" {
  default = "/home/malik/.ssh/id_rsa.pub"
}

variable "work_public_ssh_key" {
  default = "/home/malik/.ssh/work_id_rsa.pub"
}

locals {
  ssh = {
    authorized_keys = "${data.keepass_entry.phone_public_ssh_key_contents.attributes.public_key}\n${file(var.public_ssh_key)}${file(var.work_public_ssh_key)}"
  }
}

variable "keepass_database_password" { 
 sensitive = true
}

data "keepass_entry" "digitalocean_token" {
  path = "Root/DigitalOcean Token"
}

data "keepass_entry" "azure_subscription_id" {
  path = "Root/Azure Subscription ID"
}

data "keepass_entry" "azure_tenant_id" {
  path = "Root/Azure Tenancy ID"
}

data "keepass_entry" "azure_client_id" {
  path = "Root/Azure Client ID"
}

data "keepass_entry" "azure_client_secret" {
  path = "Root/Azure Client Secret"
}