variable "keepass_database_password" {
  sensitive = true
}

variable "internet_gateway_enabled" {
  default = "true"
}

variable "oke" {
  type = map(string)

  default = {
    name             = "oke"
    version          = "v1.28.2"
    shape            = "VM.Standard.A1.Flex"
    nodes_per_subnet = 3
  }
}

variable "image_id" {
  default = "ocid1.image.oc1.iad.aaaaaaaao2zpwcb2osmbtliiuzlphc3y2fqaqmcpp5ttlcf573sidkabml7a" # Oracle-Linux-8.8-aarch64-2023.09.26-0-OKE-1.28.2-653

}

variable "availability_domain" {
  default = "onUG:US-ASHBURN-AD"
}
