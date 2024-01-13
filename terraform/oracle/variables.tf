data "oci_identity_availability_domains" "ads" {
  compartment_id = module.secrets.oci_compartment_id
}

variable "keepass_database_password" {
  sensitive = true
}