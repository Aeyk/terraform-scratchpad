output "azure_subscription_id" {
  sensitive = true
  value     = module.secrets.azure_subscription_id
}

output "azure_tenant_id" {
  sensitive = true
  value     = module.secrets.azure_tenant_id
}

output "azure_client_id" {
  sensitive = true
  value     = module.secrets.azure_client_id
}

output "azure_client_secret" {
  sensitive = true
  value     = module.secrets.azure_client_secret
}
