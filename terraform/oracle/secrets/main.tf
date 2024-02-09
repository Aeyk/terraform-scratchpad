terraform {
  required_version = "~> 1.6"
  required_providers {
    keepass = {
      source  = "iSchluff/keepass"
      version = "~> 0"
    }
  }
}

provider "keepass" {
  database = "../Cloud Tokens.kdbx"
  password = var.keepass_database_password
}
