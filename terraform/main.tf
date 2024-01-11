terraform {
  required_version = "~> 1.6"
  required_providers {
    oci = {     
      source  = "oracle/oci"
      version = "~> 5"
    }
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2"
    }
    keepass = {
      source = "iSchluff/keepass"
      version = "~> 0"
    }
    aws = {
      source = "hashicorp/aws"
      version = "~> 5"
    }
  }
}

provider "aws" {
    region = "us-east-1"
    access_key = data.keepass_entry.aws_access_key.password
    secret_key = data.keepass_entry.aws_secret_key.password
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

resource "oci_identity_compartment" "cloud-mksybr" {
    compartment_id = data.keepass_entry.oci_compartment_id.password
    description = "..."
    name = "cloud-mksybr"
}

# TODO(malik): external storage for tfstate
# resource "oci_objectstorage_object" "terraform_state_storage" {
#     bucket = "terraform_state_storage"
#     content = var.object_content
#     namespace = "IAD"
#     object = var.object_object
# }


module "network" {
  source = "./network"
}

module "compute" {
  source     = "./compute"
  depends_on = [module.network]
}