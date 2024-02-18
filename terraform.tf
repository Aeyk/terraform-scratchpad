# -*- mode: ruby; -*-
variable "database_password" {
  sensitive = true
}
variable "oci_vcn_cidr_block" {}
variable "oci_vcn_public_subnet_cidr_block" {}
variable "oci_vcn_private_subnet_cidr_block" {}

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
  database = "/home/me/Cloud Tokens.kdbx"
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

resource "oci_identity_compartment" "compartment" {
  description = "Compartment for Terraform resources."
  name = "cloud.mksybr.com"
  enable_delete = true
}

resource "oci_core_vcn" "vcn" {
  depends_on = [oci_identity_compartment.compartment]
  cidr_blocks    = [var.oci_vcn_cidr_block]
  compartment_id = oci_identity_compartment.compartment.id
  is_ipv6enabled = true
  display_name   = "cloud-mksybr-vcn"
}

resource "oci_core_dhcp_options" "dhcp" {
  depends_on = [oci_identity_compartment.compartment, oci_core_vcn.vcn]
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
  depends_on = [oci_identity_compartment.compartment, oci_core_vcn.vcn]
  compartment_id = data.keepass_entry.oci_compartment_id.password
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "cloud-mksybr-igw"
}

resource "oci_core_route_table" "igw_route_table" {
  depends_on = [oci_identity_compartment.compartment, oci_core_vcn.vcn, oci_core_internet_gateway.igw]
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
  depends_on = [oci_identity_compartment.compartment, oci_core_vcn.vcn, oci_core_nat_gateway.nat_gateway]
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
  depends_on = [oci_identity_compartment.compartment, oci_core_vcn.vcn, oci_core_nat_gateway.nat_gateway, oci_core_dhcp_options.dhcp]
  compartment_id = data.keepass_entry.oci_compartment_id.password
  vcn_id         = oci_core_vcn.vcn.id
  cidr_block     = var.oci_vcn_public_subnet_cidr_block
  display_name   = "cloud-mksybr-public-subnet"
  route_table_id    = oci_core_route_table.igw_route_table.id
  dhcp_options_id   = oci_core_dhcp_options.dhcp.id
  # security_list_ids = [oci_core_security_list.public_security_list.id]
}

resource "oci_core_subnet" "private_subnet" {
  depends_on = [oci_identity_compartment.compartment, oci_core_vcn.vcn, oci_core_internet_gateway.igw, oci_core_dhcp_options.dhcp]
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

resource "oci_core_instance" "ubuntu_instance" {
  depends_on = [oci_identity_compartment.compartment, oci_core_vcn.vcn, oci_core_internet_gateway.igw, oci_core_dhcp_options.dhcp]
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
	}
	display_name = "ubuntu001-cloud-mksybr"
	instance_options {
		are_legacy_imds_endpoints_disabled = "false"
	}
	is_pv_encryption_in_transit_enabled = "true"
	metadata = {
		"ssh_authorized_keys" = file("/home/me/.ssh/id_rsa.pub")
	}
	shape = "VM.Standard.E2.1.Micro" # Always-Free includes : 2 VM.Standard.E2.1.Micro, and 4 OCPUs and 24GB of VM.Standard.A1.Flex
	shape_config {
		baseline_ocpu_utilization = "BASELINE_1_1"
		memory_in_gbs = "16"
		ocpus = "1"
	}
	source_details {
		source_id = "ocid1.image.oc1.iad.aaaaaaaaau2eo3mjbgtmjvocmvx5xbhcmj2ay3mvowdzffxhdiql5gnhxjqa"
		source_type = "image"
	}
}

# TODO network security group to allow http(s) traffic

output "compute_public_ip" {
  value = oci_core_instance.ubuntu_instance.public_ip
}

resource "digitalocean_record" "mksybr_api" {
  depends_on = [oci_core_instance.ubuntu_instance]
  name = "chat"
  domain = "mksybr.com"
  type   = "A"
  value  = oci_core_instance.ubuntu_instance.public_ip
  ttl = "30"
}
