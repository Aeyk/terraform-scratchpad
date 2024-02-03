resource "oci_core_vcn" "oke_vcn" {
  cidr_block     = lookup(var.network_cidrs, "vcn_cidr")
  compartment_id = module.secrets.oci_compartment_id

  dns_label    = "vcn1"
  display_name = "oke-vcn"
}

resource "oci_core_security_list" "oke_sl" {
  compartment_id = module.secrets.oci_compartment_id
  vcn_id         = oci_core_vcn.oke_vcn.id

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }


  ingress_security_rules {
    protocol = "all"
    source   = "0.0.0.0/0"
  }

  #Optional
  display_name = "oke-sl"
}

# https://www.terraform.io/docs/providers/oci/r/core_internet_gateway.html
resource "oci_core_internet_gateway" "oke_ig" {
  #Required
  compartment_id = module.secrets.oci_compartment_id
  vcn_id         = oci_core_vcn.oke_vcn.id

  #Optional
  enabled      = var.internet_gateway_enabled
  display_name = "oke-gateway"
}

# https://www.terraform.io/docs/providers/oci/r/core_route_table.html
resource "oci_core_route_table" "oke_rt" {
  #Required
  compartment_id = module.secrets.oci_compartment_id
  vcn_id         = oci_core_vcn.oke_vcn.id
  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.oke_ig.id
  }

  #Optional
  display_name = "oke-rt"
}

# https://www.terraform.io/docs/providers/oci/r/core_subnet.html
resource "oci_core_subnet" "worker_subnet1" {
  #Required
  cidr_block        = lookup(var.network_cidrs, "worker_subnet1")
  compartment_id    = module.secrets.oci_compartment_id
  security_list_ids = ["${oci_core_security_list.oke_sl.id}"]
  vcn_id            = oci_core_vcn.oke_vcn.id

  #Optional
  availability_domain = "${var.availability_domain}-1"
  dhcp_options_id     = oci_core_vcn.oke_vcn.default_dhcp_options_id
  display_name        = "worker_subnet1"
  dns_label           = "worker1"
  route_table_id      = oci_core_route_table.oke_rt.id
}

resource "oci_core_subnet" "worker_subnet2" {
  #Required
  cidr_block        = lookup(var.network_cidrs, "worker_subnet2")
  compartment_id    = module.secrets.oci_compartment_id
  security_list_ids = ["${oci_core_security_list.oke_sl.id}"]
  vcn_id            = oci_core_vcn.oke_vcn.id

  #Optional
  availability_domain = "${var.availability_domain}-2"
  dhcp_options_id     = oci_core_vcn.oke_vcn.default_dhcp_options_id
  display_name        = "worker_subnet2"
  dns_label           = "worker2"
  route_table_id      = oci_core_route_table.oke_rt.id
}

resource "oci_core_subnet" "worker_subnet3" {
  #Required
  cidr_block        = lookup(var.network_cidrs, "worker_subnet3")
  compartment_id    = module.secrets.oci_compartment_id
  security_list_ids = ["${oci_core_security_list.oke_sl.id}"]
  vcn_id            = oci_core_vcn.oke_vcn.id

  #Optional
  availability_domain = "${var.availability_domain}-3"
  dhcp_options_id     = oci_core_vcn.oke_vcn.default_dhcp_options_id
  display_name        = "worker_subnet3"
  dns_label           = "worker3"
  route_table_id      = oci_core_route_table.oke_rt.id
}

# resource "oci_core_subnet" "loadbalancer_subnet1" {
#   #Required
#   cidr_block        = lookup(var.network_cidrs, "loadbalancer_subnet1")
#   compartment_id    = module.secrets.oci_compartment_id
#   security_list_ids = ["${oci_core_security_list.oke_sl.id}"]
#   vcn_id            = oci_core_vcn.oke_vcn.id

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
#   vcn_id            = oci_core_vcn.oke_vcn.id

#   #Optional
#   availability_domain = var.availability_domain
#   dhcp_options_id     = oci_core_vcn.oke_vcn.default_dhcp_options_id
#   display_name        = "loadbalancer_subnet1"
#   dns_label           = "loadbalancer2"
#   route_table_id      = oci_core_route_table.oke_rt.id
# }
