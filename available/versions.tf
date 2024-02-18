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

data "keepass_entry" "aws_access_key" {
  path = "Root/AWS Access Key"
}

data "keepass_entry" "aws_secret_key" {
  path = "Root/AWS Secret Key"
}

provider "aws" {
    region = "us-east-1"
    access_key = data.keepass_entry.aws_access_key.password
    secret_key = data.keepass_entry.aws_secret_key.password
}


# resource "oci_objectstorage_object" "terraform_state_storage" {
#     bucket = "terraform_state_storage" 
#     content = var.object_content
#     namespace = "IAD"
#     object = var.object_object
# }

