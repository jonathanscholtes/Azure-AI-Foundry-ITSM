module "resource_group" {
  source = "./modules/resource_group"

  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = local.common_tags
}

module "identity" {
  source = "./modules/identity"

  managed_identity_name = var.managed_identity_name
  location              = module.resource_group.location
  resource_group_name   = module.resource_group.name
  tags                  = local.common_tags
}

module "storage" {
  source = "./modules/storage"

  storage_account_name      = var.storage_account_name
  location                  = module.resource_group.location
  resource_group_name       = module.resource_group.name
  storage_account_tier      = var.storage_account_tier
  storage_replication_type  = var.storage_replication_type
  storage_containers        = ["load", "processed", "transcript"]
  identity_principal_id     = module.identity.principal_id
  tags                      = local.common_tags
}

module "key_vault" {
  source = "./modules/key_vault"

  key_vault_name           = var.key_vault_name
  location                 = module.resource_group.location
  resource_group_name      = module.resource_group.name
  tenant_id                = module.resource_group.tenant_id
  enable_purge_protection  = var.enable_purge_protection
  identity_principal_id    = module.identity.principal_id
  tags                     = local.common_tags
}

module "search" {
  source = "./modules/search"

  search_service_name   = var.search_service_name
  location              = module.resource_group.location
  resource_group_name   = module.resource_group.name
  search_sku            = var.search_sku
  identity_principal_id = module.identity.principal_id
  tags                  = local.common_tags
}

module "container_registry" {
  source = "./modules/container_registry"

  container_registry_name = var.container_registry_name
  location                = module.resource_group.location
  resource_group_name     = module.resource_group.name
  container_registry_sku  = var.container_registry_sku
  tags                    = local.common_tags
}

module "apim" {
  source = "./modules/apim"

  apim_name              = "${var.project_name}apim${var.environment}"
  location               = module.resource_group.location
  resource_group_name    = module.resource_group.name
  publisher_name         = var.apim_publisher_name
  publisher_email        = var.apim_publisher_email
  apim_sku               = var.apim_sku
  apim_sku_capacity      = var.apim_sku_capacity
  managed_identity_id    = module.identity.id
  # Key Vault secret and identity for named value - only create if available
  # After pushing secret via PowerShell, run: terraform apply -var="key_vault_secret_identifier=<uri>" -var="identity_client_id=<client-id>"
  key_vault_secret_identifier = var.key_vault_secret_identifier
  identity_client_id          = var.identity_client_id
  tags                   = local.common_tags
}

module "monitoring" {
  source = "./modules/monitoring"

  app_insights_name   = var.app_insights_name
  location            = module.resource_group.location
  resource_group_name = module.resource_group.name
  tags                = local.common_tags
}

module "ai_services" {
  source = "./modules/ai_services"

  ai_account_name        = local.ai_account_name
  ai_project_name        = local.ai_project_name
  location               = module.resource_group.location
  resource_group_name    = module.resource_group.name
  subscription_id        = module.resource_group.subscription_id
  identity_id            = module.identity.id
  identity_principal_id  = module.identity.principal_id
  gpt4o_capacity         = var.ai_services_deployment_gpt4o_capacity
  embedding_capacity     = var.ai_services_deployment_embedding_capacity
}

# App Service Plan Module
module "apps" {
  source = "./modules/app"

  project_name        = var.project_name
  environment_name    = var.environment_name
  resource_token      = local.resource_token
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
}

# Application Module (Web Apps and Function Apps) - Optional
module "applications" {
  count  = var.deploy_applications ? 1 : 0
  source = "./modules/applications"

  project_name               = var.project_name
  environment_name           = var.environment_name
  resource_token             = local.resource_token
  location                   = var.location
  resource_group_name        = azurerm_resource_group.main.name
  managed_identity_id        = module.security.managed_identity_id
  log_analytics_workspace_name = module.monitor.log_analytics_workspace_name
  app_insights_name          = module.monitor.application_insights_name
  app_service_plan_name      = module.apps.app_service_plan_name
  key_vault_uri              = module.security.key_vault_uri
  openai_endpoint            = var.openai_endpoint != "" ? var.openai_endpoint : module.ai.openai_endpoint
  storage_account_name       = module.data.storage_account_name
  ai_account_endpoint        = module.ai.ai_account_endpoint
  cosmosdb_endpoint          = module.data.cosmosdb_endpoint

  depends_on = [
    module.apps,
    module.monitor,
    module.security,
    module.data,
    module.ai
  ]
}