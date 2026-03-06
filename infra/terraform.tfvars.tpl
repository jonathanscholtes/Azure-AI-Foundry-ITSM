subscription_id = "${SubscriptionId}"
location        = "${Location}"
environment     = "${Environment}"
project_name    = "aifoundry"
resource_token  = "${ResourceToken}"
resource_group_name = "rg-aifoundry-${Environment}-${ResourceToken}"

# Search Service
search_service_name = "aisearch-${ResourceToken}"
search_sku          = "basic"

# API Management
apim_publisher_name  = "AI Foundry ITSM"
apim_publisher_email = "admin@aifoundry.com"
apim_sku             = "Developer"
apim_sku_capacity    = 1

# Halo ITSM
halo_base_url        = "${HaloBaseUrl}"

# Storage
storage_account_name = "stg${ResourceToken}"
container_registry_name = "acr${ResourceToken}"
key_vault_name = "kv-${ResourceToken}"

# Tags
tags = {
  Environment = "${Environment}"
  Project     = "AI-Foundry-ITSM"
  ManagedBy   = "Terraform"
  CreatedAt   = "${Timestamp}"
}
