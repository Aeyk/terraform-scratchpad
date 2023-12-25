variable "database_password" { 
 sensitive = true
}

provider "keepass" {
  database = "../Cloud Tokens.kdbx"
  password = var.database_password
}

provider "digitalocean" {
  token = data.keepass_entry.digitalocean_token.password
}

provider "oci" {
  tenancy_ocid = data.keepass_entry.oci_tenancy_id.password
  user_ocid = data.keepass_entry.oci_user_id.password
  private_key_path = "/home/malik/.oci/mksybr@gmail.com_2023-12-24T00_16_14.614Z.pem"
  fingerprint = data.keepass_entry.oci_fingerprint.password
  region = "us-ashburn-1"
}