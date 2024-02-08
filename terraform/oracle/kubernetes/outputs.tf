output "subnet_id" {
  value = module.oke_vcn.subnet_id
}

locals {
  private_subnet_id = oci_core_subnet.private.id
  public_subnet_id  = oci_core_subnet.public.id
}
