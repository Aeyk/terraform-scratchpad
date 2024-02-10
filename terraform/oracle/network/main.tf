terraform {
  required_version = "~> 1.6"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5"
    }
    keepass = {
      source  = "iSchluff/keepass"
      version = "~> 0"
    }
  }
}

provider "keepass" {
  database = "/home/malik/Documents/Cloud Tokens.kdbx"
  password = var.keepass_database_password
}

module "secrets" {
  source                    = "../secrets"
  keepass_database_password = var.keepass_database_password
}

resource "oci_core_vcn" "vcn" {
  depends_on     = [data.keepass_entry.oci_compartment_id]
  cidr_blocks    = [var.oci_vcn_cidr_block]
  compartment_id = data.keepass_entry.oci_compartment_id.password
  is_ipv6enabled = true
  display_name   = "vcn"
}

resource "oci_core_dhcp_options" "dhcp" {
  depends_on     = [oci_core_vcn.vcn]
  compartment_id = data.keepass_entry.oci_compartment_id.password
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "dhcp-options"
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
  depends_on     = [oci_core_vcn.vcn]
  compartment_id = data.keepass_entry.oci_compartment_id.password
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "igw"
}

# resource "oci_core_default_security_list" "default_list" {
#   manage_default_resource_id = oci_core_vcn.vcn.default_list

#   display_name = "Outbound only (default)"

#   egress_security_rules {
#     protocol    = "all" // TCP
#     description = "Allow outbound"
#     destination = "0.0.0.0/0"
#   }
#   ingress_security_rules {
#     protocol    = "all"
#     description = "Allow inter-subnet traffic"
#     source      = "0.0.0.0/0"
#   }
# }

resource "oci_core_route_table" "igw_route_table" {
  depends_on     = [oci_core_vcn.vcn, oci_core_internet_gateway.igw]
  compartment_id = data.keepass_entry.oci_compartment_id.password
  # manage_default_resource_id = oci_core_vcn.vcn.default_route_table_id
  vcn_id       = oci_core_vcn.vcn.id
  display_name = "igw-route-table"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

resource "oci_core_route_table" "igw_ipv6_route_table" {
  depends_on     = [oci_core_vcn.vcn, oci_core_internet_gateway.igw]
  compartment_id = data.keepass_entry.oci_compartment_id.password
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "igw-ipv6-route-table"

  route_rules {
    destination       = "::/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

# resource "oci_core_nat_gateway" "nat_gateway" {
#   depends_on = [oci_core_vcn.vcn]
#   compartment_id = data.keepass_entry.oci_compartment_id.password
#   vcn_id         = oci_core_vcn.vcn.id
#   display_name   = "nat-gateway"
# }

# resource "oci_core_route_table" "nat_route_table" {
#   depends_on = [oci_core_vcn.vcn, oci_core_nat_gateway.nat_gateway]
#   compartment_id = data.keepass_entry.oci_compartment_id.password
#   vcn_id         = oci_core_vcn.vcn.id
#   display_name   = "nat-route-table"
#   route_rules {
#     destination       = "0.0.0.0/0"
#     destination_type  = "CIDR_BLOCK"
#     network_entity_id = oci_core_nat_gateway.nat_gateway.id
#   }
# }

resource "oci_core_subnet" "public" {
  depends_on = [oci_core_vcn.vcn,
    # oci_core_nat_gateway.nat_gateway,
  oci_core_dhcp_options.dhcp]
  compartment_id = data.keepass_entry.oci_compartment_id.password
  vcn_id         = oci_core_vcn.vcn.id
  cidr_block     = var.oci_vcn_public_subnet_cidr_block
  # ipv6cidr_block = var.oci_vcn_public_subnet_ipv6_cidr_block
  display_name    = "public-subnet"
  route_table_id  = oci_core_route_table.igw_route_table.id
  dhcp_options_id = oci_core_dhcp_options.dhcp.id
  # security_list_ids = [oci_core_security_list.public.id]
}

resource "oci_core_subnet" "private" {
  depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
  oci_core_dhcp_options.dhcp]
  compartment_id = data.keepass_entry.oci_compartment_id.password
  vcn_id         = oci_core_vcn.vcn.id
  cidr_block     = var.oci_vcn_private_subnet_cidr_block
  # ipv6cidr_block = var.oci_vcn_private_subnet_ipv6_cidr_block
  display_name               = "private-subnet"
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.igw_route_table.id
  dhcp_options_id            = oci_core_dhcp_options.dhcp.id
  # security_list_ids = [oci_core_security_list.private_security_list.id]
}

resource "oci_core_network_security_group" "public" {
  depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
  oci_core_dhcp_options.dhcp]
  display_name   = "network-security-group"
  compartment_id = data.keepass_entry.oci_compartment_id.password
  vcn_id         = oci_core_vcn.vcn.id
}

resource "oci_core_network_security_group_security_rule" "tcp4_http_ingress" {
  depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
  oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.public.id
  protocol                  = 6 # TCP
  direction                 = "INGRESS"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless                 = "true"
  tcp_options {
    destination_port_range {
      min = 80
      max = 80
    }
  }
}

resource "oci_core_network_security_group_security_rule" "tcp6_http_ingress" {
  depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
  oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.public.id
  protocol                  = 6 # TCP
  direction                 = "INGRESS"
  source                    = "::/0"
  source_type               = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless                 = "true"
  tcp_options {
    destination_port_range {
      min = 80
      max = 80
    }
  }
}

resource "oci_core_network_security_group_security_rule" "tcp4_https_ingress" {
  depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
  oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.public.id
  protocol                  = 6 # TCP
  direction                 = "INGRESS"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless                 = "true"
  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

resource "oci_core_network_security_group_security_rule" "tcp6_https_ingress" {
  depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
  oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.public.id
  protocol                  = 6 # TCP
  direction                 = "INGRESS"
  source                    = "::/0"
  source_type               = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless                 = "true"
  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

resource "oci_core_network_security_group_security_rule" "icmp_ingress" {
  depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
  oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.public.id
  protocol                  = 1 # ICMP
  direction                 = "INGRESS"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless                 = "true"
}

resource "oci_core_network_security_group_security_rule" "icmpv6_ingress" {
  depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
  oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.public.id
  protocol                  = 58 # ICMPv6
  direction                 = "INGRESS"
  source                    = "::/0"
  source_type               = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless                 = "true"
}

resource "oci_core_network_security_group_security_rule" "tcp4_kubernetes_ingress" {
  depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
  oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.public.id
  protocol                  = 6 # TCP
  direction                 = "INGRESS"
  source                    = "10.0.0.0/24"
  source_type               = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless                 = "true"
  tcp_options {
    destination_port_range {
      min = 6443
      max = 6443
    }
  }
}

# resource "oci_core_network_security_group_security_rule" "tcp6_kubernetes_ingress" {
#   depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
#   oci_core_dhcp_options.dhcp]
#   network_security_group_id = oci_core_network_security_group.public.id
#   protocol                  = 6 # TCP
#   direction                 = "INGRESS"
#   source                    = "::/0"
#   source_type               = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
#   stateless                 = "true"
#   tcp_options {
#     destination_port_range {
#       min = 6443
#       max = 6443
#     }
#   }
# }

resource "oci_core_network_security_group_security_rule" "tcp4_ingress_etcd" {
  depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
  oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.public.id
  count                     = 4
  protocol                  = 6 # TCP
  direction                 = "INGRESS"
  # source = "${oci_core_instance.arm-1vcpu-6gb-us-qas[count.index].public_ip}/32"
  source      = "10.0.0.0/24"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless   = "true"
  tcp_options {
    destination_port_range {
      min = 2379
      max = 2381
    }
  }
}

# resource "oci_core_network_security_group_security_rule" "tcp6_ingress_etcd" {
#   depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
#   oci_core_dhcp_options.dhcp]
#   network_security_group_id = oci_core_network_security_group.public.id
#   count                     = 4
#   protocol                  = 6 # TCP
#   direction                 = "INGRESS"
#   # source = "${oci_core_instance.arm-1vcpu-6gb-us-qas[count.index].public_ip}/32"
#   source      = "::/0"
#   source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
#   stateless   = "true"
#   tcp_options {
#     destination_port_range {
#       min = 2379
#       max = 2381
#     }
#   }
# }

resource "oci_core_network_security_group_security_rule" "tcp4_nodeports" {
  depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
  oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.public.id
  count                     = 4
  protocol                  = 6 # TCP
  direction                 = "INGRESS"
  # source = "${oci_core_instance.arm-1vcpu-6gb-us-qas[count.index].public_ip}/32"
  source      = "10.0.0.0/24"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless   = "true"
  tcp_options {
    destination_port_range {
      min = 30000
      max = 32767
    }
  }
}

# resource "oci_core_network_security_group_security_rule" "tcp6_nodeports" {
#   depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
#   oci_core_dhcp_options.dhcp]
#   network_security_group_id = oci_core_network_security_group.public.id
#   count                     = 4
#   protocol                  = 6 # TCP
#   direction                 = "INGRESS"
#   # source = "${oci_core_instance.arm-1vcpu-6gb-us-qas[count.index].public_ip}/32"
#   source      = "::/0"
#   source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
#   stateless   = "true"
#   tcp_options {
#     destination_port_range {
#       min = 30000
#       max = 32767
#     }
#   }
# }

resource "oci_core_network_security_group_security_rule" "tcp4_kubelet" {
  depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
  oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.public.id
  count                     = 4
  protocol                  = 6 # TCP
  direction                 = "INGRESS"
  # source = "${oci_core_instance.arm-1vcpu-6gb-us-qas[count.index].public_ip}/32"
  source      = "10.0.0.0/24"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless   = "true"
  tcp_options {
    destination_port_range {
      min = 10248
      max = 10259
    }
  }
}

# resource "oci_core_network_security_group_security_rule" "tcp6_nodeports" {
#   depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
#   oci_core_dhcp_options.dhcp]
#   network_security_group_id = oci_core_network_security_group.public.id
#   count                     = 4
#   protocol                  = 6 # TCP
#   direction                 = "INGRESS"
#   # source = "${oci_core_instance.arm-1vcpu-6gb-us-qas[count.index].public_ip}/32"
#   source      = "::/0"
#   source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
#   stateless   = "true"
#   tcp_options {
#     destination_port_range {
#       min = 10248
#       max = 10259
#     }
#   }
# }

resource "oci_core_network_security_group_security_rule" "tcp4_metallb" {
  depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
  oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.public.id
  count                     = 4
  protocol                  = 6 # TCP
  direction                 = "INGRESS"
  # source = "${oci_core_instance.arm-1vcpu-6gb-us-qas[count.index].public_ip}/32"
  source      = "10.0.0.0/24"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless   = "true"
  tcp_options {
    destination_port_range {
      min = 7472
      max = 7472
    }
  }
}

# resource "oci_core_network_security_group_security_rule" "tcp6_metallb" {
#   depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
#   oci_core_dhcp_options.dhcp]
#   network_security_group_id = oci_core_network_security_group.public.id
#   count                     = 4
#   protocol                  = 6 # TCP
#   direction                 = "INGRESS"
#   # source = "${oci_core_instance.arm-1vcpu-6gb-us-qas[count.index].public_ip}/32"
#   source      = "::/0"
#   source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
#   stateless   = "true"
#   tcp_options {
#     destination_port_range {
#       min = 7472
#       max = 7472
#     }
#   }
# }

resource "oci_core_network_security_group_security_rule" "tcp4_metallb2" {
  depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
  oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.public.id
  count                     = 4
  protocol                  = 6 # TCP
  direction                 = "INGRESS"
  # source = "${oci_core_instance.arm-1vcpu-6gb-us-qas[count.index].public_ip}/32"
  source      = "10.0.0.0/24"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless   = "true"
  tcp_options {
    destination_port_range {
      min = 7946
      max = 7946
    }
  }
}

# resource "oci_core_network_security_group_security_rule" "tcp6_metallb2" {
#   depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
#   oci_core_dhcp_options.dhcp]
#   network_security_group_id = oci_core_network_security_group.public.id
#   count                     = 4
#   protocol                  = 6 # TCP
#   direction                 = "INGRESS"
#   # source = "${oci_core_instance.arm-1vcpu-6gb-us-qas[count.index].public_ip}/32"
#   source      = "::/0"
#   source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
#   stateless   = "true"
#   tcp_options {
#     destination_port_range {
#       min = 7496
#       max = 7496
#     }
#   }
# }

resource "oci_core_network_security_group_security_rule" "udp4_metallb" {
  depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
  oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.public.id
  count                     = 4
  protocol                  = 17 # UDP
  direction                 = "INGRESS"
  # source = "${oci_core_instance.arm-1vcpu-6gb-us-qas[count.index].public_ip}/32"
  source      = "10.0.0.0/24"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless   = "true"
  udp_options {
    destination_port_range {
      min = 7472
      max = 7472
    }
  }
}

# resource "oci_core_network_security_group_security_rule" "udp6_metallb" {
#   depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
#   oci_core_dhcp_options.dhcp]
#   network_security_group_id = oci_core_network_security_group.public.id
#   count                     = 4
#   protocol                  = 17 # UDP
#   direction                 = "INGRESS"
#   # source = "${oci_core_instance.arm-1vcpu-6gb-us-qas[count.index].public_ip}/32"
#   source      = "::/0"
#   source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
#   stateless   = "true"
#   udp_options {
#     destination_port_range {
#       min = 7472
#       max = 7472
#     }
#   }
# }

resource "oci_core_network_security_group_security_rule" "udp4_metallb2" {
  depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
  oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.public.id
  count                     = 4
  protocol                  = 17 # UDP
  direction                 = "INGRESS"
  # source = "${oci_core_instance.arm-1vcpu-6gb-us-qas[count.index].public_ip}/32"
  source      = "10.0.0.0/24"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless   = "true"
  udp_options {
    destination_port_range {
      min = 7946
      max = 7946
    }
  }
}

# resource "oci_core_network_security_group_security_rule" "udp6_metallb2" {
#   depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
#   oci_core_dhcp_options.dhcp]
#   network_security_group_id = oci_core_network_security_group.public.id
#   count                     = 4
#   protocol                  = 17 # UDP
#   direction                 = "INGRESS"
#   # source = "${oci_core_instance.arm-1vcpu-6gb-us-qas[count.index].public_ip}/32"
#   source      = "::/0"
#   source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
#   stateless   = "true"
#   udp_options {
#     destination_port_range {
#       min = 7496
#       max = 7496
#     }
#   }
# }

resource "oci_core_network_security_group_security_rule" "tcp4_calico" {
  depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
  oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.public.id
  count                     = 4
  protocol                  = 6 # TCP
  direction                 = "INGRESS"
  # source = "${oci_core_instance.arm-1vcpu-6gb-us-qas[count.index].public_ip}/32"
  source      = "10.0.0.0/24"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless   = "true"
  tcp_options {
    destination_port_range {
      min = 9099
      max = 9099
    }
  }
}

# resource "oci_core_network_security_group_security_rule" "tcp6_calico" {
#   depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
#   oci_core_dhcp_options.dhcp]
#   network_security_group_id = oci_core_network_security_group.public.id
#   count                     = 4
#   protocol                  = 6 # TCP
#   direction                 = "INGRESS"
#   # source = "${oci_core_instance.arm-1vcpu-6gb-us-qas[count.index].public_ip}/32"
#   source      = "::/0"
#   source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
#   stateless   = "true"
#   tcp_options {
#     destination_port_range {
#       min = 179
#       max = 179
#     }
#   }
# }

resource "oci_core_network_security_group_security_rule" "tcp4_kube-rbac" {
  depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
  oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.public.id
  count                     = 4
  protocol                  = 6 # TCP
  direction                 = "INGRESS"
  # source = "${oci_core_instance.arm-1vcpu-6gb-us-qas[count.index].public_ip}/32"
  source      = "10.0.0.0/24"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless   = "true"
  tcp_options {
    destination_port_range {
      min = 9100
      max = 9100
    }
  }
}

# resource "oci_core_network_security_group_security_rule" "tcp6_kube-rbac" {
#   depends_on = [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
#   oci_core_dhcp_options.dhcp]
#   network_security_group_id = oci_core_network_security_group.public.id
#   count                     = 4
#   protocol                  = 6 # TCP
#   direction                 = "INGRESS"
#   # source = "${oci_core_instance.arm-1vcpu-6gb-us-qas[count.index].public_ip}/32"
#   source      = "::/0"
#   source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
#   stateless   = "true"
#   tcp_options {
#     destination_port_range {
#       min = 9100
#       max = 9100
#     }
#   }
# }




