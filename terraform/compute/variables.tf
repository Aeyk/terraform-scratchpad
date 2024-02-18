variable "amd-1vcpu-1gb-us-qas_count" {
  default = 2
}

variable "arm-1vcpu-6gb-us-qas_count" {
  default = 4
}

data "oci_core_ipv6s" "amd-1vcpu-1gb-us-qas-ipv6" {
    count = var.amd-1vcpu-1gb-us-qas_count
    subnet_id = oci_core_subnet.public_subnet.id
}