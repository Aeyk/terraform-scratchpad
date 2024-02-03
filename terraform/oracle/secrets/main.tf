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
  database = var.keepass_database
  password = var.keepass_database_password
}
