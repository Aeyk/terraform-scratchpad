# -*- mode: ruby; -*-
variable "database_password" {
  sensitive = true
}
variable "oci_vcn_cidr_block" {}
variable "oci_vcn_public_subnet_cidr_block" {}
variable "oci_vcn_private_subnet_cidr_block" {}

variable "public_ssh_key" {
  default = "/home/me/.ssh/id_rsa.pub"
}

terraform {
  required_providers {
    oci = {     
      source  = "oracle/oci"
      version = "5.0.0"
    }
    digitalocean = {
      source = "digitalocean/digitalocean"
      version = "2.28.1"
    }
    keepass = {
      source = "iSchluff/keepass"
      version = "0.2.1"
    }
  }
}

provider "keepass" {
  database = "./Cloud Tokens.kdbx"
  password = var.database_password
}

data "keepass_entry" "digitalocean_token" {
  path = "Root/DigitalOcean Token"
}
data "keepass_entry" "oci_fingerprint" {
  path = "Root/Oracle OCI fingerprint"
}
data "keepass_entry" "oci_tenancy_id" {
  path = "Root/Oracle Tenancy ID"
}
data "keepass_entry" "oci_compartment_id" {
  path = "Root/Oracle Compartment ID"
}
data "keepass_entry" "oci_user_id" {
  path = "Root/Oracle User ID"
}

provider "digitalocean" {
  token = data.keepass_entry.digitalocean_token.password
}

provider "oci" {
  tenancy_ocid = data.keepass_entry.oci_tenancy_id.password
  user_ocid = data.keepass_entry.oci_user_id.password
  private_key_path = "/home/me/.config/oci/oracle_free.pem"
  fingerprint = data.keepass_entry.oci_fingerprint.password
  region = "us-ashburn-1"
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = data.keepass_entry.oci_compartment_id.password
}

data "oci_identity_compartment" "compartment" {
  id = data.keepass_entry.oci_compartment_id.password
}

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

resource "oci_core_nat_gateway" "nat_gateway" {
  depends_on = [oci_core_vcn.vcn]
  compartment_id = data.keepass_entry.oci_compartment_id.password
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "cloud-mksybr-nat-gateway"
}

resource "oci_core_route_table" "nat_route_table" {
  depends_on = [oci_core_vcn.vcn, oci_core_nat_gateway.nat_gateway]
  compartment_id = data.keepass_entry.oci_compartment_id.password
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "cloud-mksybr-nat-route-table"
  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.nat_gateway.id
  }
}

resource "oci_core_subnet" "public_subnet" {
  depends_on = [oci_core_vcn.vcn, oci_core_nat_gateway.nat_gateway,
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

output "all-availability-domains-in-your-tenancy" {
  value = data.oci_identity_availability_domains.ads.availability_domains
}

output "vcn_id" {
  description = "id of vcn that is created"
  value       = oci_core_vcn.vcn.id
}

locals {
  common_tags = {
    vcn_id = oci_core_vcn.vcn.id
  }
}

resource "oci_core_network_security_group" "cloud_net_security_group" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  display_name = "cloud-mksybr-network-security-group"
  compartment_id = data.keepass_entry.oci_compartment_id.password
  vcn_id = oci_core_vcn.vcn.id
}

resource "oci_core_network_security_group" "me_net_security_group" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  display_name = "me-mksybr-network-security-group"
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


resource "oci_core_network_security_group_security_rule" "rdp_ingress" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.me_net_security_group.id
  protocol = 6 # ICMPv6
  direction = "INGRESS"
  source = "172.58.0.0/16"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless = "false"
  tcp_options {
    destination_port_range {
      min = 3389
      max = 3389
    }
  }
}

resource "oci_core_network_security_group_security_rule" "rdpv6_ingress" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  network_security_group_id = oci_core_network_security_group.me_net_security_group.id
  protocol = 6 # ICMPv6
  direction = "INGRESS"
  source = "2607:fb91:180d::/48"
  source_type = "CIDR_BLOCK" # todo replace with NETWORK_SECURITY_GROUP
  stateless = "false"
  tcp_options {
    destination_port_range {
      min = 3389
      max = 3389
    }
  }
}

resource "oci_core_instance" "ubuntu_instance" {
  depends_on = [
    oci_core_vcn.vcn, oci_core_internet_gateway.igw,
    oci_core_dhcp_options.dhcp,
    oci_core_network_security_group.cloud_net_security_group,

    oci_core_network_security_group_security_rule.ipv4_http_ingress,
    oci_core_network_security_group_security_rule.ipv6_http_ingress,
    
    oci_core_network_security_group_security_rule.ipv4_https_ingress,
    oci_core_network_security_group_security_rule.ipv6_https_ingress,

    oci_core_network_security_group_security_rule.icmp_ingress,
    oci_core_network_security_group_security_rule.icmpv6_ingress,

    oci_core_network_security_group_security_rule.identd_ingress,
    oci_core_network_security_group_security_rule.identdv6_ingress,
  ]
  display_name = "ubuntu000-cloud-mksybr"
	agent_config {
		is_management_disabled = "false"
		is_monitoring_disabled = "false"
		plugins_config {
			desired_state = "DISABLED"
			name = "Vulnerability Scanning"
		}
		plugins_config {
			desired_state = "DISABLED"
			name = "Management Agent"
		}
		plugins_config {
			desired_state = "ENABLED"
			name = "Custom Logs Monitoring"
		}
		plugins_config {
			desired_state = "ENABLED"
			name = "Compute Instance Monitoring"
		}
		plugins_config {
			desired_state = "DISABLED"
			name = "Bastion"
		}
	}
	availability_config {
		is_live_migration_preferred = "true"
		recovery_action = "RESTORE_INSTANCE"
	}
	availability_domain = "onUG:US-ASHBURN-AD-3"
	compartment_id = data.keepass_entry.oci_compartment_id.password
	create_vnic_details {
		assign_private_dns_record = "false"
		assign_public_ip = "true"
		subnet_id = oci_core_subnet.public_subnet.id
		nsg_ids = [oci_core_network_security_group.cloud_net_security_group.id]
	}
	instance_options {
		are_legacy_imds_endpoints_disabled = "false"
	}
	is_pv_encryption_in_transit_enabled = "true"
	metadata = {
		"ssh_authorized_keys" = file(var.public_ssh_key)
	}
  # Always-Free includes : 2 VM.Standard.E2.1.Micro
	shape = "VM.Standard.E2.1.Micro"
	source_details {
		source_id = "ocid1.image.oc1.iad.aaaaaaaaau2eo3mjbgtmjvocmvx5xbhcmj2ay3mvowdzffxhdiql5gnhxjqa"
		source_type = "image"
	}
}

resource "oci_core_instance" "arm_instance" {
  depends_on = [
    oci_core_vcn.vcn, oci_core_internet_gateway.igw,
    oci_core_dhcp_options.dhcp,
    oci_core_network_security_group.me_net_security_group,   
    oci_core_network_security_group_security_rule.rdp_ingress,
    oci_core_network_security_group_security_rule.rdpv6_ingress
  ]
  display_name = "ubuntu001-cloud-mksybr"
	agent_config {
		is_management_disabled = "false"
		is_monitoring_disabled = "false"
		plugins_config {
			desired_state = "DISABLED"
			name = "Vulnerability Scanning"
		}
		plugins_config {
			desired_state = "DISABLED"
			name = "Management Agent"
		}
		plugins_config {
			desired_state = "ENABLED"
			name = "Custom Logs Monitoring"
		}
		plugins_config {
			desired_state = "ENABLED"
			name = "Compute Instance Monitoring"
		}
		plugins_config {
			desired_state = "DISABLED"
			name = "Bastion"
		}
	}
	availability_config {
		is_live_migration_preferred = "true"
		recovery_action = "RESTORE_INSTANCE"
	}
	availability_domain = "onUG:US-ASHBURN-AD-2"
	compartment_id = data.keepass_entry.oci_compartment_id.password
	create_vnic_details {
		assign_private_dns_record = "false"
		assign_public_ip = "true"
		subnet_id = oci_core_subnet.public_subnet.id
		nsg_ids = [oci_core_network_security_group.cloud_net_security_group.id]
	}
	instance_options {
		are_legacy_imds_endpoints_disabled = "false"
	}
	is_pv_encryption_in_transit_enabled = "true"
	metadata = {
		"ssh_authorized_keys" = file(var.public_ssh_key)
	}
  # Month of free ampere instances
  # Free monthly ampere credits are:
  # VM.Standard.A1.Flex and 4 OCPUs and 24GB
  shape = "VM.Standard.A1.Flex"
	shape_config {
		baseline_ocpu_utilization = "BASELINE_1_1"
		memory_in_gbs = "24"
		ocpus = "4"
	}
	source_details {
		source_id = "ocid1.image.oc1.iad.aaaaaaaavubwxrc4xy3coabavp7da7ltjnfath6oe3h6nxrgxx7pr67xp6iq"
		source_type = "image"
	}
}

output "ubuntu_public_ip" {
  value = oci_core_instance.ubuntu_instance.public_ip
}

output "arm_public_ip" {
  value = oci_core_instance.arm_instance.public_ip
}

resource "digitalocean_record" "chat-mksybr-com-dns-record" {
  depends_on = [oci_core_instance.ubuntu_instance]
  name = "chat"
  domain = "mksybr.com"
  type   = "A"
  value  = oci_core_instance.ubuntu_instance.public_ip
  ttl = "30"
}

resource "digitalocean_record" "me-mksybr-com-dns-record" {
  depends_on = [oci_core_instance.arm_instance]
  name = "me"
  domain = "mksybr.com"
  type   = "A"
  value  = oci_core_instance.arm_instance.public_ip
  ttl = "30"
}
