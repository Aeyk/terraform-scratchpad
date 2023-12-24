locals {
  ssh = {
    authorized_keys = "${data.keepass_entry.phone_public_ssh_key_contents.attributes.public_key}\n${file(var.public_ssh_key)}"
  }
}