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

resource "oci_core_subnet" "public" {
  depends_on     = [module.oke_vcn]
  compartment_id = module.secrets.oci_compartment_id
  vcn_id         = module.oke_vcn.vcn_id
  cidr_block     = "10.0.1.0/24"
  # ipv6cidr_block = var.oci_vcn_public_subnet_ipv6_cidr_block
  display_name = "public-subnet"
  # route_table_id    = oci_core_route_table.igw_route_table.id
  # dhcp_options_id   = oci_core_dhcp_options.dhcp.id
  # security_list_ids = [oci_core_security_list.default_security_list_id]
}

resource "oci_core_subnet" "private" {
  compartment_id             = module.secrets.oci_compartment_id
  vcn_id                     = module.oke_vcn.vcn_id
  cidr_block                 = "10.0.2.0/24"
  route_table_id             = module.oke_vcn.nat_route_id
  security_list_ids          = [oci_core_security_list.private.id]
  display_name               = "k8s_private_subnet"
  prohibit_public_ip_on_vnic = true
}

resource "oci_core_security_list" "private" {
  compartment_id = module.secrets.oci_compartment_id
  vcn_id         = module.oke_vcn.vcn_id
  display_name   = "k8s_private_subnet"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    protocol = "all"
    source   = "10.0.0.0/16"
  }
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
  display_name   = "k8s-public-subnet-sl"

  # egress everywhere
  egress_security_rules {
    stateless        = false
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
  }

  # ingres only our cidr
  ingress_security_rules {
    stateless   = false
    source      = "10.0.0.0/16"
    source_type = "CIDR_BLOCK"
    protocol    = "all"
  }

  # ingress from internet on k8s-api
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
