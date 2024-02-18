resource "oci_core_network_security_group" "me_net_security_group" {
  depends_on =  [oci_core_vcn.vcn, oci_core_internet_gateway.igw,
                 oci_core_dhcp_options.dhcp]
  display_name = "me-mksybr-network-security-group"
  compartment_id = data.keepass_entry.oci_compartment_id.password
  vcn_id = oci_core_vcn.vcn.id
}

resource "oci_core_instance" "arm_instance" {
  depends_on = [
    oci_core_vcn.vcn, oci_core_internet_gateway.igw,
    oci_core_dhcp_options.dhcp,
    oci_core_network_security_group.me_net_security_group,   
    oci_core_network_security_group_security_rule.rdp_ingress,
    oci_core_network_security_group_security_rule.rdpv6_ingress
  ]
  display_name = "me-cloud-mksybr-us-qas-000"
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
	source_id = "ocid1.image.oc1.iad.aaaaaaaavubwxrc4xy3coabavp7da7ltjnfath6oe3h6nxrgxx7pr67xp6iq"
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
    host     = "${oci_core_instance.ubuntu_instance.public_ip}"
  }
}

output "arm_public_ip" {
  value = oci_core_instance.arm_instance.public_ip
}

resource "digitalocean_record" "me-mksybr-com-dns-record" {
  depends_on = [oci_core_instance.arm_instance]
  name = "me"
  domain = "mksybr.com"
  type   = "A"
  value  = oci_core_instance.arm_instance.public_ip
  ttl = "30"
}
