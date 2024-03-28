
variable "oci_vcn_cidr_block" {
  default = "10.0.0.0/16"
}

variable "oci_vcn_public_subnet_cidr_block" {
  default = "10.0.0.0/24"
}

variable "oci_vcn_public_subnet_ipv6_cidr_block" {
  default = "2603:c020:4014:dc00::/56"
}

variable "oci_vcn_private_subnet_cidr_block" {
  default = "10.0.1.0/24"
}

variable "oci_vcn_private_subnet_ipv6_cidr_block" {
  default = "2603:c020:4014:dc00::/56"
}

data "keepass_entry" "oci_compartment_id" {
  path = "Root/Oracle Compartment ID"
}

variable "keepass_database_password" {
  sensitive = true
}
