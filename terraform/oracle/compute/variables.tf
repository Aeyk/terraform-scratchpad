variable "amd-1vcpu-1gb-us-qas_count" {
  default = 0
}

variable "arm-1vcpu-6gb-us-qas_count" {
  default = 4
}

data "oci_core_ipv6s" "amd-1vcpu-1gb-us-qas-ipv6" {
    count = var.amd-1vcpu-1gb-us-qas_count
    subnet_id = "${module.network.arm_public_subnet}"
}

variable "keepass_database_password" {
  sensitive = true
}