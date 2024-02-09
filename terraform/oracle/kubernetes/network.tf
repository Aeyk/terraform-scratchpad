# resource "oci_core_vcn" "oke_vcn" {
#   cidr_block     = lookup(var.network_cidrs, "vcn_cidr")
#   compartment_id = module.secrets.oci_compartment_id

#   dns_label    = "vcn1"
#   display_name = "oke-vcn"
# }

module "oke_vcn" {
  source                       = "oracle-terraform-modules/vcn/oci"
  version                      = "3.6.0"
  compartment_id               = module.secrets.oci_compartment_id
  region                       = "us-ashburn-1"
  internet_gateway_route_rules = null
  local_peering_gateways       = null
  nat_gateway_route_rules      = null
  vcn_name                     = "k8s-vcn"
  vcn_dns_label                = "k8svcn"
  vcn_cidrs                    = ["10.0.0.0/16"]
  create_internet_gateway      = true
  create_nat_gateway           = true
  create_service_gateway       = true
}


variable "private_cidr_block" {
  default = "10.0.1.0/24"
}

variable "public_cidr_block" {
  default = "10.0.0.0/24"
}
# resource "oci_core_subnet" "public" {
#   compartment_id    = module.secrets.oci_compartment_id
#   vcn_id            = module.oke_vcn.vcn_id
#   cidr_block        = "10.1.0.0/24"
#   display_name      = "k8s_public_subnet"
#   route_table_id    = module.oke_vcn.ig_route_id
#   security_list_ids = [oci_core_security_list.public.id]
# }

resource "oci_core_security_list" "public" {
  compartment_id = module.secrets.oci_compartment_id
  vcn_id         = module.oke_vcn.vcn_id
  display_name   = "public"
  egress_security_rules {
    stateless        = false
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
  }
  ingress_security_rules {
    stateless   = false
    source      = "10.0.0.0/16"
    source_type = "CIDR_BLOCK"
    protocol    = "all"
  }
  ingress_security_rules {
    stateless   = false
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    protocol    = "6"
    tcp_options {
      min = 6443
      max = 6443
    }
  }
}

# https://www.terraform.io/docs/providers/oci/r/core_internet_gateway.html
# resource "oci_core_internet_gateway" "oke_ig" {
#   #Required
#   compartment_id = module.secrets.oci_compartment_id
#   vcn_id         = module.oke_vcn.vcn_id

#   #Optional
#   enabled      = var.internet_gateway_enabled
#   display_name = "oke-gateway"
# }

# # https://www.terraform.io/docs/providers/oci/r/core_route_table.html
# resource "oci_core_route_table" "oke_rt" {
#   #Required
#   compartment_id = module.secrets.oci_compartment_id
#   vcn_id         = module.oke_vcn.vcn_id
#   route_rules {
#     destination       = "0.0.0.0/0"
#     network_entity_id = oci_core_internet_gateway.oke_ig.id
#   }

#   #Optional
#   display_name = "oke-rt"
# }


# # https://www.terraform.io/docs/providers/oci/r/core_subnet.html
# resource "oci_core_subnet" "worker_subnet1" {
#   #Required
#   cidr_block        = lookup(var.network_cidrs, "worker_subnet1")
#   compartment_id    = module.secrets.oci_compartment_id
#   security_list_ids = ["${oci_core_security_list.oke_sl.id}"]
#   vcn_id            = module.oke_vcn.vcn_id

#   #Optional
#   availability_domain = "${var.availability_domain}-1"
#   dhcp_options_id     = oci_core_vcn.oke_vcn.default_dhcp_options_id
#   display_name        = "worker_subnet1"
#   dns_label           = "worker1"
#   route_table_id      = oci_core_route_table.oke_rt.id
# }

# resource "oci_core_subnet" "worker_subnet2" {
#   #Required
#   cidr_block        = lookup(var.network_cidrs, "worker_subnet2")
#   compartment_id    = module.secrets.oci_compartment_id
#   security_list_ids = ["${oci_core_security_list.oke_sl.id}"]
#   vcn_id            = oci_core_vcn.

#   #Optional
#   availability_domain = "${var.availability_domain}-2"
#   dhcp_options_id     = oci_core_vcn.oke_vcn.default_dhcp_options_id
#   display_name        = "worker_subnet2"
#   dns_label           = "worker2"
#   route_table_id      = oci_core_route_table.oke_rt.id
# }

# resource "oci_core_subnet" "worker_subnet3" {
#   #Required
#   cidr_block        = lookup(var.network_cidrs, "worker_subnet3")
#   compartment_id    = module.secrets.oci_compartment_id
#   security_list_ids = ["${oci_core_security_list.oke_sl.id}"]
#   vcn_id            = module.oke_vcn.vcn_id

#   #Optional
#   availability_domain = "${var.availability_domain}-3"
#   dhcp_options_id     = oci_core_vcn.oke_vcn.default_dhcp_options_id
#   display_name        = "worker_subnet3"
#   dns_label           = "worker3"
#   route_table_id      = oci_core_route_table.oke_rt.id
# }

# resource "oci_core_subnet" "loadbalancer_subnet1" {
#   #Required
#   cidr_block        = lookup(var.network_cidrs, "loadbalancer_subnet1")
#   compartment_id    = module.secrets.oci_compartment_id
#   security_list_ids = ["${oci_core_security_list.oke_sl.id}"]
#   vcn_id            = module.oke_vcn.vcn_id

#   #Optional
#   availability_domain = var.availability_domain
#   dhcp_options_id     = oci_core_vcn.oke_vcn.default_dhcp_options_id
#   display_name        = "loadbalancer_subnet1"
#   dns_label           = "loadbalancer1"
#   route_table_id      = oci_core_route_table.oke_rt.id
# }

# resource "oci_core_subnet" "loadbalancer_subnet2" {
#   #Required
#   cidr_block        = lookup(var.network_cidrs, "loadbalancer_subnet2")
#   compartment_id    = module.secrets.oci_compartment_id
#   security_list_ids = ["${oci_core_security_list.oke_sl.id}"]
#   vcn_id            = module.oke_vcn.vcn_id

#   #Optional
#   availability_domain = var.availability_domain
#   dhcp_options_id     = oci_core_vcn.oke_vcn.default_dhcp_options_id
#   display_name        = "loadbalancer_subnet1"
#   dns_label           = "loadbalancer2"
#   route_table_id      = oci_core_route_table.oke_rt.id
# }
