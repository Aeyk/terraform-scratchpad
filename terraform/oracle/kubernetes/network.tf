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

resource "oci_core_security_list" "private" {
  compartment_id = module.secrets.oci_compartment_id
  vcn_id         = module.oke_vcn.vcn_id
  display_name   = "private"
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
}

resource "oci_core_subnet" "private" {
  compartment_id             = module.secrets.oci_compartment_id
  vcn_id                     = module.oke_vcn.vcn_id
  cidr_block                 = var.private_cidr_block
  route_table_id             = module.oke_vcn.nat_route_id
  security_list_ids          = [oci_core_security_list.private.id]
  display_name               = "private"
  prohibit_public_ip_on_vnic = true
  prohibit_internet_ingress  = true
}

resource "oci_core_subnet" "public" {
  depends_on                 = [module.oke_vcn]
  compartment_id             = module.secrets.oci_compartment_id
  vcn_id                     = module.oke_vcn.vcn_id
  cidr_block                 = var.public_cidr_block
  display_name               = "public"
  route_table_id             = module.oke_vcn.ig_route_id
  security_list_ids          = [oci_core_security_list.public.id]
  prohibit_public_ip_on_vnic = false
  prohibit_internet_ingress  = false
  # dhcp_options_id   = oci_core_dhcp_options.dhcp.id
  # ipv6cidr_block = var.oci_vcn_public_subnet_ipv6_cidr_block
}
