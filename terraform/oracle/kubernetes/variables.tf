variable "keepass_database_password" {
  sensitive = true
}

variable "internet_gateway_enabled" {
  default = "true"
}

variable "worker_ol_image_name" {
  default = "Oracle-Linux-7.5"
}

variable "oke" {
  type = map(string)

  default = {
    name             = "oke"
    version          = "v1.28.2"
    shape            = "VM.Standard.A1.Flex"
    nodes_per_subnet = 1
  }
}

variable "network_cidrs" {
  type = map(string)

  default = {
    vcn_cidr             = "10.0.0.0/16"
    worker_subnet1       = "10.0.1.0/24"
    worker_subnet2       = "10.0.2.0/24"
    worker_subnet3       = "10.0.3.0/24"
    loadbalancer_subnet1 = "10.0.4.0/24"
    loadbalancer_subnet2 = "10.0.5.0/24"
    loadbalancer_subnet3 = "10.0.6.0/24"
  }
}

variable "image_id" {
  default = "ocid1.image.oc1.iad.aaaaaaaao2zpwcb2osmbtliiuzlphc3y2fqaqmcpp5ttlcf573sidkabml7a" # Oracle-Linux-8.8-aarch64-2023.09.26-0-OKE-1.28.2-653

}

variable "availability_domain" {
  default = "onUG:US-ASHBURN-AD"
}
