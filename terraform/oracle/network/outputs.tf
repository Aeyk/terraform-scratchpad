output "vcn_id" {
  description = "id of vcn that is created"
  value       = oci_core_vcn.vcn.id
}

output "arm_public_subnet" {
  value = oci_core_subnet.public.id
}

output "arm_net_security_group" {
  value = oci_core_network_security_group.public.id
}
