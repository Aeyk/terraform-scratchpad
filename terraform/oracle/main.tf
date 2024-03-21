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
  backend "http" {
    update_method = "PUT"
    address = "https://objectstorage.us-ashburn-1.oraclecloud.com/p/hVXK-nOJRhpgFgEbMQc35cfRgno05l1koEdjvOmPP14Vkcd_6c0Z543_G0E3yMHp/n/idt66ykl9mui/b/terraform/o/terraform.tfstate"
  }
}

# resource "oci_objectstorage_bucket" "terraform" {
#     compartment_id = module.secrets.oci_compartment_id
#     name = "terraform"
#     namespace = "idt66ykl9mui"
# }

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
  fingerprint = module.secrets.oci_fingerprint
  # oci session authenticate --profile-name DEFAULT 
  auth = "SecurityToken" 
  config_file_profile = "DEFAULT"
  region = "us-ashburn-1" 
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

module "kubernetes" {
  keepass_database_password = var.keepass_database_password
  source = "./kubernetes"
}

