variable "private_ssh_key" {
  default = "/home/malik/.ssh/id_rsa"
}

data "keepass_entry" "phone_public_ssh_key_contents" {
  path = "Root/Phone Key"
}

variable "public_ssh_key" {
  default = "/home/malik/.ssh/id_rsa.pub"
}

locals {
  ssh = {
    authorized_keys = "${data.keepass_entry.phone_public_ssh_key_contents.attributes.public_key}\n${file(var.public_ssh_key)}"
  }
}