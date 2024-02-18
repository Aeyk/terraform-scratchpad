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
  token = module.secrets.digitalocean_token
}

provider "oci" {
  tenancy_ocid = module.secrets.oci_tenancy_id
  user_ocid = module.secrets.oci_user_id
  private_key_path = "/home/malik/.oci/mksybr@gmail.com_2023-12-24T00_16_14.614Z.pem"
  fingerprint = module.secrets.oci_fingerprint
  region = "us-ashburn-1"
}

# TODO(malik): external storage for tfstate
resource "oci_objectstorage_object" "terraform_state_storage" {
    bucket = "terraform_state_storage"
    content = var.object_content
    namespace = "IAD"
    object = var.object_object
}

data "terraform_remote_state" "terraform_state" {
  backend = "s3"

  config = {
    organization = "hashicorp"
    workspaces = {
      name = "vpc-prod"
    }
  }
}

module "network" {
  keepass_database_password = var.keepass_database_password
  source = "./network"
}

module "compute" {
  keepass_database_password = var.keepass_database_password  
  source     = "./compute"
}

module "secrets" {
  source = "./secrets"
  keepass_database_password = var.keepass_database_password
}
