output "oci_compartment_id" {
    value = data.keepass_entry.oci_compartment_id.password
}

output "database_password" {
    value = var.keepass_database_password
}

output "oci_fingerprint" {
    value = data.keepass_entry.oci_fingerprint.password
}

output "oci_user_id" {
    value = data.keepass_entry.oci_user_id.password
}

output "oci_tenancy_id" {
    value = data.keepass_entry.oci_tenancy_id.password
}

output "digitalocean_token" {
   value = data.keepass_entry.digitalocean_token.password
}

output "ssh_authorized_keys" {
  value = "${data.keepass_entry.phone_public_ssh_key_contents.attributes.public_key}\n${file(var.public_ssh_key)}${file(var.work_public_ssh_key)}"
}

output "private_ssh_key" {
  value = var.private_ssh_key
}
