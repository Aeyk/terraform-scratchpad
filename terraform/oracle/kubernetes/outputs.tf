output "public_nsg_id" {
  value = oci_core_security_list.public.id
}
output "private_nsg_id" {
  value = oci_core_security_list.private.id
}
output "public_subnet_id" {
  value = oci_core_subnet.public.id
}
output "private_subnet_id" {
  value = oci_core_subnet.public.id
}
output "subnet_id" {
  value = module.oke_vcn.subnet_id
}

locals {
  private_subnet_id = oci_core_subnet.private.id
  public_subnet_id  = oci_core_subnet.public.id
}
