
resource "oci_identity_compartment" "cloud-mksybr" {
    compartment_id = data.keepass_entry.oci_compartment_id.password
    description = "..."
    name = "cloud-mksybr"
}