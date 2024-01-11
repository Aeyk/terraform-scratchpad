terraform {
  required_version = "~> 1.6"
  required_providers {
    oci = {     
      source  = "oracle/oci"
      version = "~> 5"
    }
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2"
    }
    keepass = {
      source = "iSchluff/keepass"
      version = "~> 0"
    }
  }
}

provider "keepass" {
  database = "../Cloud Tokens.kdbx"
  password = var.keepass_database_password
}

module "network" {
  source = "../network"
  keepass_database_password = var.keepass_database_password
}

module "secrets" {
  source = "../secrets"
  keepass_database_password = var.keepass_database_password
}

resource "oci_core_network_security_group" "me_net_security_group" {
  display_name = "me-mksybr-network-security-group"
  compartment_id = module.secrets.oci_compartment_id
  vcn_id = module.network.vcn_id
}

resource "oci_core_instance" "arm-1vcpu-6gb-us-qas" {
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
  compartment_id = module.secrets.oci_compartment_id
  create_vnic_details {
    assign_private_dns_record = "false"
    assign_public_ip = "true"
    subnet_id = module.network.arm_public_subnet
    nsg_ids = [module.network.arm_net_security_group]
    # assign_ipv6ip = "true"
  }
  instance_options {
    are_legacy_imds_endpoints_disabled = "false"
  }
  is_pv_encryption_in_transit_enabled = "true"
  metadata = {
    "ssh_authorized_keys" = module.secrets.ssh_authorized_keys
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
    subnet_id = module.network.arm_public_subnet
}

# resource "digitalocean_record" "arm-1vcpu-6gb-us-qas-a-dns-record" {
#   depends_on = [oci_core_instance.arm-1vcpu-6gb-us-qas]
#   count = var.arm-1vcpu-6gb-us-qas_count
#   name = "a"
#   domain = "mksybr.com"
#   type   = "A"
#   value  = oci_core_instance.arm-1vcpu-6gb-us-qas[count.index].public_ip
#   ttl = "30"
# }

# resource "digitalocean_record" "keycloak-arm-1vcpu-6gb-us-qas-a-dns-record" {
#   depends_on = [oci_core_instance.arm-1vcpu-6gb-us-qas]
#   count = var.arm-1vcpu-6gb-us-qas_count
#   name = "keycloak"
#   domain = "mksybr.com"
#   type   = "A"
#   value  = oci_core_instance.arm-1vcpu-6gb-us-qas[count.index].public_ip
#   ttl = "30"
# }

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

resource "oci_core_instance" "amd-1vcpu-1gb-us-qas" {
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
  # compartment_id = data.keepass_entry.oci_compartment_id.password
  compartment_id = module.secrets.oci_compartment_id
  create_vnic_details {
    assign_private_dns_record = "false"
    assign_public_ip = "true"
    # assign_ipv6ip = "true"
    subnet_id = module.network.arm_public_subnet
    nsg_ids = [module.network.arm_net_security_group]
    # nsg_ids = [oci_core_network_security_group.cloud_net_security_group.id]
  }
  instance_options {
    are_legacy_imds_endpoints_disabled = "false"
  }
  is_pv_encryption_in_transit_enabled = "true"
  metadata = {
    "ssh_authorized_keys" = module.secrets.ssh_authorized_keys
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

resource "local_file" "ansible_inventory" {
  content = templatefile("../ansible/inventory.ini.tmpl", {
    # amd-1vcpu-1gb-us-qas-public_ipv4 = oci_core_instance.amd-1vcpu-1gb-us-qas.*.public_ip
    arm-1vcpu-6gb-us-qas-public_ipv4 = oci_core_instance.arm-1vcpu-6gb-us-qas.*.public_ip
  })
  filename = "../ansible/inventory.ini"
}