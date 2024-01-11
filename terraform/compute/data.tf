data "oci_core_ipv6s" "amd-1vcpu-1gb-us-qas-ipv6" {
    #Required
    count = var.amd-1vcpu-1gb-us-qas_count
    subnet_id = oci_core_subnet.public_subnet.id
}