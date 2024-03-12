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
    authorized_keys = "${data.keepass_entry.phone_public_ssh_key_contents.attributes.public_key}\n${file(var.public_ssh_key)}${data.keepass_entry.work_public_ssh_key}"
  }
}

variable "keepass_database_password" { 
 sensitive = true
}

data "keepass_entry" "aws_access_key" {
  path = "Root/AWS Access Key"
}

data "keepass_entry" "aws_secret_key" {
  path = "Root/AWS Secret Key"
}

data "keepass_entry" "digitalocean_token" {
  path = "Root/DigitalOcean Token"
}

data "keepass_entry" "oci_fingerprint" {
  path = "Root/Oracle OCI fingerprint"
}

data "keepass_entry" "oci_tenancy_id" {
  path = "Root/Oracle Tenancy ID"
}

data "keepass_entry" "oci_user_id" {
  path = "Root/Oracle User ID"
}


data "keepass_entry" "oci_compartment_id" {
  path = "Root/Oracle Compartment ID"
}

data "keepass_entry" "work_public_ssh_key" {
  path = "Root/Work Public SSH Key"
}
