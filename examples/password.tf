terraform {
  required_providers {
    keepass = {
      source = "iSchluff/keepass"
      version = "0.2.1"
    }
  }
}

variable "database_password" {
  sensitive = true
}

provider "keepass" {
  database = "../Cloud Tokens.kdbx"
  password = var.database_password
}

data "keepass_entry" "phone_public_ssh_key_contents" {
  path = "Root/Phone Key"

}

variable "public_ssh_key" {
  default = "/home/me/.ssh/id_rsa.pub"
}

locals {
  ssh = {
    authorized_keys = "${data.keepass_entry.phone_public_ssh_key_contents.attributes.public_key}\n${file(var.public_ssh_key)}"
  }
}
