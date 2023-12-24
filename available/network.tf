
resource "oci_core_vcn" "vcn" {
  cidr_blocks    = [var.oci_vcn_cidr_block]
  compartment_id = data.oci_identity_compartment.compartment.id
  is_ipv6enabled = true
  display_name   = "cloud-mksybr-vcn"
}

resource "oci_core_dhcp_options" "dhcp" {
  depends_on = [oci_core_vcn.vcn]
  compartment_id = data.keepass_entry.oci_compartment_id.password
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "cloud-mksybr-dhcp-options"
  options {
    type        = "DomainNameServer"
    server_type = "VcnLocalPlusInternet"
  }
  options {
    type                = "SearchDomain"
    search_domain_names = ["mksybr.com"]
  }
}

resource "oci_core_internet_gateway" "igw" {
  depends_on = [oci_core_vcn.vcn]
  compartment_id = data.keepass_entry.oci_compartment_id.password
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "cloud-mksybr-igw"
}

resource "oci_core_route_table" "igw_route_table" {
  depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw]
  compartment_id = data.keepass_entry.oci_compartment_id.password
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "cloud-mksybr-igw-route-table"
  
  route_rules {
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

# resource "oci_core_nat_gateway" "nat_gateway" {
#   depends_on = [oci_core_vcn.vcn]
#   compartment_id = data.keepass_entry.oci_compartment_id.password
#   vcn_id         = oci_core_vcn.vcn.id
#   display_name   = "cloud-mksybr-nat-gateway"
# }

# resource "oci_core_route_table" "nat_route_table" {
#   depends_on = [oci_core_vcn.vcn, oci_core_nat_gateway.nat_gateway]
#   compartment_id = data.keepass_entry.oci_compartment_id.password
#   vcn_id         = oci_core_vcn.vcn.id
#   display_name   = "cloud-mksybr-nat-route-table"
#   route_rules {
#     destination       = "0.0.0.0/0"
#     destination_type  = "CIDR_BLOCK"
#     network_entity_id = oci_core_nat_gateway.nat_gateway.id
#   }
# }

resource "oci_core_subnet" "public_subnet" {
  depends_on = [oci_core_vcn.vcn,
                # oci_core_nat_gateway.nat_gateway,
                oci_core_dhcp_options.dhcp]
  compartment_id = data.keepass_entry.oci_compartment_id.password
  vcn_id         = oci_core_vcn.vcn.id
  cidr_block     = var.oci_vcn_public_subnet_cidr_block
  display_name   = "cloud-mksybr-public-subnet"
  route_table_id    = oci_core_route_table.igw_route_table.id
  dhcp_options_id   = oci_core_dhcp_options.dhcp.id
  # security_list_ids = [oci_core_security_list.public_security_list.id]
}

resource "oci_core_subnet" "private_subnet" {
  depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                oci_core_dhcp_options.dhcp]
  compartment_id = data.keepass_entry.oci_compartment_id.password
  vcn_id         = oci_core_vcn.vcn.id
  cidr_block     = var.oci_vcn_private_subnet_cidr_block
  display_name   = "cloud-mksybr-private-subnet"
  prohibit_public_ip_on_vnic = true
  route_table_id    = oci_core_route_table.igw_route_table.id
  dhcp_options_id   = oci_core_dhcp_options.dhcp.id
  # security_list_ids = [oci_core_security_list.private_security_list.id]
}

output "vcn_id" {
  description = "id of vcn that is created"
  value       = oci_core_vcn.vcn.id
}

resource "oci_core_network_security_group" "cloud_net_security_group" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  display_name = "cloud-mksybr-network-security-group"
  compartment_id = data.keepass_entry.oci_compartment_id.password
  vcn_id = oci_core_vcn.vcn.id
}

resource "oci_core_network_security_group_security_rule" "ipv4_http_ingress" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.cloud_net_security_group.id
  protocol = 6 # TCP
  direction = "INGRESS"
  source = "0.0.0.0/0"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless = "false"
  tcp_options {
    destination_port_range {
      min = 80
      max = 80
    }
  }   
}


resource "oci_core_network_security_group_security_rule" "ipv6_http_ingress" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.cloud_net_security_group.id
  protocol = 6 # TCP
  direction = "INGRESS"
  source = "::/0"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless = "false"
  tcp_options {
    destination_port_range {
      min = 80
      max = 80
    }
  }
}

resource "oci_core_network_security_group_security_rule" "ipv4_https_ingress" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.cloud_net_security_group.id
  protocol = 6 # TCP
  direction = "INGRESS"
  source = "0.0.0.0/0"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless = "false"
  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }   
}

resource "oci_core_network_security_group_security_rule" "ipv6_https_ingress" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.cloud_net_security_group.id
  protocol = 6 # TCP
  direction = "INGRESS"
  source = "::/0"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless = "false"
  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }   
}

resource "oci_core_network_security_group_security_rule" "ipv4_caprover_ingress" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.cloud_net_security_group.id
  protocol = 6 # TCP
  direction = "INGRESS"
  source = "0.0.0.0/0"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless = "false"
  tcp_options {
    destination_port_range {
      min = 3000
      max = 3000
    }
  }   
}

resource "oci_core_network_security_group_security_rule" "ipv6_caprover_ingress" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.cloud_net_security_group.id
  protocol = 6 # TCP
  direction = "INGRESS"
  source = "::/0"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless = "false"
  tcp_options {
    destination_port_range {
      min = 3000
      max = 3000
    }
  }
}

resource "oci_core_network_security_group_security_rule" "ipv4_https_docker_ingress" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.cloud_net_security_group.id
  protocol = 6 # TCP
  direction = "INGRESS"
  source = "0.0.0.0/0"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless = "false"
  tcp_options {
    destination_port_range {
      min = 996
      max = 996
    }
  }   
}

resource "oci_core_network_security_group_security_rule" "ipv6_https_docker_ingress" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.cloud_net_security_group.id
  protocol = 6 # TCP
  direction = "INGRESS"
  source = "::/0"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless = "false"
  tcp_options {
    destination_port_range {
      min = 996
      max = 996
    }
  }
}

resource "oci_core_network_security_group_security_rule" "tcp4_container_network_discovery_ingress" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.cloud_net_security_group.id
  protocol = 6 # TCP
  direction = "INGRESS"
  source = "0.0.0.0/0"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless = "false"
  tcp_options {
    destination_port_range {
      min = 7946
      max = 7946
    }
  }   
}

resource "oci_core_network_security_group_security_rule" "tcp6_container_network_discovery_ingress" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.cloud_net_security_group.id
  protocol = 6 # TCP
  direction = "INGRESS"
  source = "::/0"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless = "false"
  tcp_options {
    destination_port_range {
      min = 7946
      max = 7946
    }
  }
}

resource "oci_core_network_security_group_security_rule" "tcp4_container_overlay_network_ingress" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.cloud_net_security_group.id
  protocol = 6 # TCP
  direction = "INGRESS"
  source = "0.0.0.0/0"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless = "false"
  tcp_options {
    destination_port_range {
      min = 4789
      max = 4789
    }
  }   
}

resource "oci_core_network_security_group_security_rule" "tcp6_container_overlay_network_ingress" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.cloud_net_security_group.id
  protocol = 6 # TCP
  direction = "INGRESS"
  source = "::/0"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless = "false"
  tcp_options {
    destination_port_range {
      min = 4789
      max = 4789
    }
  }
}

resource "oci_core_network_security_group_security_rule" "tcp4_docker_swarm_api_ingress" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.cloud_net_security_group.id
  protocol = 6 # TCP
  direction = "INGRESS"
  source = "0.0.0.0/0"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless = "false"
  tcp_options {
    destination_port_range {
      min = 2377
      max = 2377
    }
  }   
}

resource "oci_core_network_security_group_security_rule" "udp4_docker_swarm_api_ingress" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.cloud_net_security_group.id
  protocol = 17 # UDP
  direction = "INGRESS"
  source = "0.0.0.0/0"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless = "false"
  udp_options {
    destination_port_range {
      min = 2377
      max = 2377
    }
  }
}
resource "oci_core_network_security_group_security_rule" "udp6_docker_swarm_api_ingress" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.cloud_net_security_group.id
  protocol = 17 # UDP
  direction = "INGRESS"
  source = "::/0"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless = "false"
  udp_options {
    destination_port_range {
      min = 2377
      max = 2377
    }
  }
}

resource "oci_core_network_security_group_security_rule" "udp4_container_network_discovery_ingress" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.cloud_net_security_group.id
  protocol = 17 # UDP
  direction = "INGRESS"
  source = "0.0.0.0/0"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless = "false"
  udp_options {
    destination_port_range {
      min = 7946
      max = 7946
    }
  }   
}

resource "oci_core_network_security_group_security_rule" "udp6_container_network_discovery_ingress" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.cloud_net_security_group.id
  protocol = 17 # UDP
  direction = "INGRESS"
  source = "::/0"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless = "false"
  udp_options {
    destination_port_range {
      min = 4789
      max = 4789
    }
  }
}

resource "oci_core_network_security_group_security_rule" "udp4_container_overlay_network_ingress" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.cloud_net_security_group.id
  protocol = 17 # UDP
  direction = "INGRESS"
  source = "0.0.0.0/0"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless = "false"
  udp_options {
    destination_port_range {
      min = 4789
      max = 4789
    }
  }   
}

resource "oci_core_network_security_group_security_rule" "udp6_container_overlay_network_ingress" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.cloud_net_security_group.id
  protocol = 17 # UDP
  direction = "INGRESS"
  source = "::/0"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless = "false"
  udp_options {
    destination_port_range {
      min = 4789
      max = 4789
    }
  }
}

resource "oci_core_network_security_group_security_rule" "ipv4_docker_swarm_api_ingress" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.cloud_net_security_group.id
  protocol = 17 # UDP
  direction = "INGRESS"
  source = "0.0.0.0/0"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless = "false"
  udp_options {
    destination_port_range {
      min = 2377
      max = 2377
    }
  }   
}

resource "oci_core_network_security_group_security_rule" "ipv6_docker_swarm_api_ingress" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.cloud_net_security_group.id
  protocol = 6 # TCP
  direction = "INGRESS"
  source = "::/0"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless = "false"
  tcp_options {
    destination_port_range {
      min = 2377
      max = 2377
    }
  }
}


resource "oci_core_network_security_group_security_rule" "icmp_ingress" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.cloud_net_security_group.id
  protocol = 1 # ICMP
  direction = "INGRESS"
  source = "0.0.0.0/0"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless = "true"
}

resource "oci_core_network_security_group_security_rule" "icmpv6_ingress" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.cloud_net_security_group.id
  protocol = 58 # ICMPv6
  direction = "INGRESS"
  source = "::/0"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless = "true"
}

resource "oci_core_network_security_group_security_rule" "identd_ingress" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.cloud_net_security_group.id
  protocol = 6 # ICMPv6
  direction = "INGRESS"
  source = "0.0.0.0/0"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless = "false"
  tcp_options {
    destination_port_range {
      min = 113
      max = 113
    }
  }
}

resource "oci_core_network_security_group_security_rule" "identdv6_ingress" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.cloud_net_security_group.id
  protocol = 6 # ICMPv6
  direction = "INGRESS"
  source = "::/0"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless = "false"
  tcp_options {
    destination_port_range {
      min = 113
      max = 113
    }
  }
}


# resource "oci_core_network_security_group_security_rule" "rdp_ingress" {
#   depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
#                  oci_core_dhcp_options.dhcp]
#   network_security_group_id = oci_core_network_security_group.me_net_security_group.id
#   protocol = 6 # ICMPv6
#   direction = "INGRESS"
#   source = "172.56.0.0/16"
#   source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
#   stateless = "false"
#   tcp_options {
#     destination_port_range {
#       min = 3389
#       max = 3389
#     }
#   }
# }

# resource "oci_core_network_security_group_security_rule" "rdpv6_ingress" {
#   depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
#                  oci_core_dhcp_options.dhcp]
#   network_security_group_id = oci_core_network_security_group.me_net_security_group.id
#   protocol = 6 # ICMPv6
#   direction = "INGRESS"
#   source = "2607:fb90:e210::/48"
#   source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
#   stateless = "false"
#   tcp_options {
#     destination_port_range {
#       min = 3389
#       max = 3389
#     }
#   }
# }