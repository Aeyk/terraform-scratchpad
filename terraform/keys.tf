data "keepass_entry" "digitalocean_token" {
  path = "Root/DigitalOcean Token"
}
data "keepass_entry" "oci_fingerprint" {
  path = "Root/Oracle OCI fingerprint"
}
data "keepass_entry" "oci_tenancy_id" {
  path = "Root/Oracle Tenancy ID"
}
data "keepass_entry" "oci_compartment_id" {
  path = "Root/Oracle Compartment ID"
}
data "keepass_entry" "oci_user_id" {
  path = "Root/Oracle User ID"
}
