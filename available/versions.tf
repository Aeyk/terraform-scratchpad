data "keepass_entry" "aws_access_key" {
  path = "Root/AWS Access Key"
}

data "keepass_entry" "aws_secret_key" {
  path = "Root/AWS Secret Key"
}

# resource "oci_objectstorage_object" "terraform_state_storage" {
#     bucket = "terraform_state_storage" 
#     content = var.object_content
#     namespace = "IAD"
#     object = var.object_object
# }

