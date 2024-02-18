# -*- mode: ruby; -*-
variable "database_password" { 
 sensitive = true
}

variable "oci_vcn_cidr_block" {
  default = "10.0.0.0/24"
}
variable "oci_vcn_public_subnet_cidr_block" {
  default = "10.0.0.0/28"
}
variable "oci_vcn_private_subnet_cidr_block" {
  default = "10.0.0.16/28"
}

variable "private_ssh_key" {
  default = "/home/malik/.ssh/id_rsa"
}

provider "keepass" {
  database = "../Cloud Tokens.kdbx"
  password = var.database_password
}

provider "digitalocean" {
  token = data.keepass_entry.digitalocean_token.password
}

provider "oci" {
  tenancy_ocid = data.keepass_entry.oci_tenancy_id.password
  user_ocid = data.keepass_entry.oci_user_id.password
  private_key_path = "/home/me/.oci/cloud_mksybr.pem"
  fingerprint = data.keepass_entry.oci_fingerprint.password
  region = "us-ashburn-1"
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = data.keepass_entry.oci_compartment_id.password
}

data "oci_identity_compartment" "compartment" {
  id = data.keepass_entry.oci_compartment_id.password
}

output "all-availability-domains-in-your-tenancy" {
  value = data.oci_identity_availability_domains.ads.availability_domains
}

locals {
  common_tags = {
    vcn_id = oci_core_vcn.vcn.id
  }
}

variable "amd64_instance_count" {
  default = 2
}

resource "oci_core_instance" "amd64_instance" {
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
  count = var.amd64_instance_count
  display_name = "amd-1vcpu-1gb-us-qas-00${count.index}"
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
    # assign_ipv6ip = "true"
    subnet_id = oci_core_subnet.public_subnet.id
    nsg_ids = [oci_core_network_security_group.cloud_net_security_group.id]
  }
  instance_options {
    are_legacy_imds_endpoints_disabled = "false"
  }
  is_pv_encryption_in_transit_enabled = "true"
  metadata = {
    "ssh_authorized_keys" = local.ssh.authorized_keys
  }
  # Always-Free includes : 2 VM.Standard.E2.1.Micro
  shape = "VM.Standard.E2.1.Micro"
  source_details {
    source_id = "ocid1.image.oc1.iad.aaaaaaaaau2eo3mjbgtmjvocmvx5xbhcmj2ay3mvowdzffxhdiql5gnhxjqa"
    source_type = "image"
  }
  # provisioner "file" {
  #   source = "${oci_core_instance.amd64_instance.display_name}-installer.sh"
  #   destination = "/tmp/installer.sh"
  # }
  # provisioner "remote-exec" {
  #   inline = [
  #     "chmod +x /tmp/installer.sh",
  #     "sudo /tmp/installer.sh"
  #   ]
  # }  
  connection {
    type     = "ssh"
    user     = "ubuntu"
    private_key = "${file(var.private_ssh_key)}"
    host     = "${self.public_ip}"
  }
}

output "ubuntu_public_ips" {
  value = [for u in oci_core_instance.amd64_instance : u.public_ip[*]]
}

resource "digitalocean_record" "amd-1vcpu-1gb-us-qas-a-dns-record" {
  depends_on = [oci_core_instance.amd64_instance]
  count = var.amd64_instance_count
  name = "b"
  domain = "mksybr.com"
  type   = "A"
  value  = oci_core_instance.amd64_instance[count.index].public_ip
  ttl = "30"
}

# resource "digitalocean_record" "amd-1vcpu-1gb-us-qas-aaaa-dns-record" {
#   depends_on = [oci_core_instance.amd64_instance]
#   count = var.amd64_instance_count
#   name = "b"
#   domain = "mksybr.com"
#   type   = "AAAA"
#   value  = oci_core_instance.amd64_instance[count.index].public_ipv6
#   ttl = "30"
# }
