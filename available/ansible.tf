resource "local_file" "ansible_inventory" {
  content = templatefile("../ansible/inventory.ini.tmpl", {
    # amd-1vcpu-1gb-us-qas-public_ipv4 = oci_core_instance.amd-1vcpu-1gb-us-qas.*.public_ip
    arm-1vcpu-6gb-us-qas-public_ipv4 = oci_core_instance.arm-1vcpu-6gb-us-qas.*.public_ip
    arm-1vcpu-6gb-us-qas-private_ipv4 = oci_core_instance.arm-1vcpu-6gb-us-qas.*.private_ip
  })
  filename = "../ansible/inventory.ini"
}


