output "ubuntu_public_ips" {
  value = [for u in oci_core_instance.amd-1vcpu-1gb-us-qas : u.public_ip[*]]
}

output "arm_public_ips" {
  value = [for u in oci_core_instance.arm-1vcpu-6gb-us-qas : u.public_ip[*]]
}
