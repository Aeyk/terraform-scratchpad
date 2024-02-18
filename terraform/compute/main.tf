resource "oci_core_network_security_group" "me_net_security_group" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                  oci_core_dhcp_options.dhcp]
  display_name = "me-mksybr-network-security-group"
  compartment_id = data.keepass_entry.oci_compartment_id.password
  vcn_id = oci_core_vcn.vcn.id
}

resource "oci_core_instance" "arm-1vcpu-6gb-us-qas" {
  depends_on = [
    oci_core_vcn.vcn, oci_core_internet_gateway.igw,
    oci_core_dhcp_options.dhcp,
    oci_core_network_security_group.me_net_security_group,
    oci_core_subnet.public_subnet,
    oci_core_subnet.private_subnet
    # oci_core_network_security_group_security_rule.rdp_ingress,
    # oci_core_network_security_group_security_rule.rdpv6_ingress
  ]
  count = var.arm-1vcpu-6gb-us-qas_count
  display_name = "arm-1vcpu-6gb-us-qas-00${count.index}"
  agent_config {
    is_management_disabled = "false"
    is_monitoring_disabled = "false"
    plugins_config {
      desired_state = "DISABLED"
      name = "Vulnerability Scanning"
    }
    plugins_config {
      desired_state = "ENABLED"
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
    # assign_ipv6ip = "true"
  }
  instance_options {
    are_legacy_imds_endpoints_disabled = "false"
  }
  is_pv_encryption_in_transit_enabled = "true"
  metadata = {
    "ssh_authorized_keys" = local.ssh.authorized_keys
  }
  # Month of free ampere instances
  # Free monthly ampere credits are:
  # VM.Standard.A1.Flex and 4 OCPUs and 24GB
  shape = "VM.Standard.A1.Flex"
  shape_config {
    baseline_ocpu_utilization = "BASELINE_1_1"
    memory_in_gbs = "6"
    ocpus = "1"
  }
  source_details {
  # source_id = "ocid1.image.oc1.iad.aaaaaaaavubwxrc4xy3coabavp7da7ltjnfath6oe3h6nxrgxx7pr67xp6iq" # Oracle Linux 9 doesn't have support for OLCNE on AArch64
    source_id = "ocid1.image.oc1.iad.aaaaaaaa65b4p3cuexre4cfwkyig4js4qcv7sekhp3syhed5h4y4de3b4xja" 
    source_type = "image"
  }
  # provisioner "file" {
  #   source = "${oci_core_instance.ubuntu_instance.display_name}-installer.sh"
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

data "oci_core_ipv6s" "arm-1vcpu-6gb-us-qas-ipv6" {
    #Required
    # count = var.arm-1vcpu-6gb-us-qas_count
    subnet_id = oci_core_subnet.public_subnet.id
}

resource "digitalocean_record" "arm-1vcpu-6gb-us-qas-a-dns-record" {
  depends_on = [oci_core_instance.arm-1vcpu-6gb-us-qas]
  count = var.arm-1vcpu-6gb-us-qas_count
  name = "a"
  domain = "mksybr.com"
  type   = "A"
  value  = oci_core_instance.arm-1vcpu-6gb-us-qas[count.index].public_ip
  ttl = "30"
}

resource "digitalocean_record" "keycloak-arm-1vcpu-6gb-us-qas-a-dns-record" {
  depends_on = [oci_core_instance.arm-1vcpu-6gb-us-qas]
  count = var.arm-1vcpu-6gb-us-qas_count
  name = "keycloak"
  domain = "mksybr.com"
  type   = "A"
  value  = oci_core_instance.arm-1vcpu-6gb-us-qas[count.index].public_ip
  ttl = "30"
}

# resource "aws_ses_domain_identity" "zulip_domain" {
#   domain = "zulip.mksybr.com"
# }
# 
# resource "aws_ses_domain_identity_verification" "zulip_domain_verification" {
#   domain = aws_ses_domain_identity.zulip_domain.id
#   depends_on = [aws_ses_domain_identity.zulip_domain]
# }
# 

# resource "digitalocean_record" "arm-1vcpu-6gb-us-qas-cname-dns-record" {
#   depends_on = [aws_ses_domain_identity.zulip_domain]
#   name = "cname"
#   domain = "zulip.mksybr.com"
#   type   = "CNAME"
#   value  = aws_ses_domain_identity.zulip_domain.verification_token
#   ttl = "30"
# }

# -*- mode: ruby; -*-
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

variable "amd-1vcpu-1gb-us-qas_count" {
  default = 2
}

resource "oci_core_instance" "amd-1vcpu-1gb-us-qas" {
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
  count = var.amd-1vcpu-1gb-us-qas_count
  display_name = "amd-1vcpu-1gb-us-qas-00${count.index}"
  agent_config {
	is_management_disabled = "false"
	is_monitoring_disabled = "false"
	plugins_config {
	  desired_state = "DISABLED"
	  name = "Vulnerability Scanning"
	}
	plugins_config {
	  desired_state = "ENABLED"
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
  #   source = "${oci_core_instance.amd-1vcpu-1gb-us-qas.display_name}-installer.sh"
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

resource "digitalocean_record" "amd-1vcpu-1gb-us-qas-a-dns-record" {
  depends_on = [oci_core_instance.amd-1vcpu-1gb-us-qas]
  count = var.amd-1vcpu-1gb-us-qas_count
  name = "b"
  domain = "mksybr.com"
  type   = "A"
  value  = oci_core_instance.amd-1vcpu-1gb-us-qas[count.index].public_ip
  ttl = "30"
}

# resource "digitalocean_record" "amd-1vcpu-1gb-us-qas-aaaa-dns-record" {
#   depends_on = [oci_core_instance.amd-1vcpu-1gb-us-qas]
#   count = var.amd-1vcpu-1gb-us-qas_count
#   name = "b"
#   domain = "mksybr.com"
#   type   = "AAAA"
#   value  =  oci_core_ipv6s.amd-1vcpu-1gb-us-qas-ipv6.ipv6s
#   ttl = "30"
# }


