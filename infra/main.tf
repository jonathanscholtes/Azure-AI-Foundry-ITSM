module "resource_group" {
  source = "./modules/resource_group"

  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = local.common_tags
}

# Current deploying user context (for role assignments)
data "azurerm_client_config" "current" {}

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

  apim_name              = "${var.project_name}apim${var.resource_token}"
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
  halo_base_url          = var.halo_base_url
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
  gpt41_capacity         = var.ai_services_deployment_gpt41_capacity
  embedding_capacity     = var.ai_services_deployment_embedding_capacity
}

# ================================================
# Deploying User Role Assignments
# These allow the workshop participant to create/manage Foundry agents
# and invoke AI services from the notebook and portal.
# ================================================

# Azure AI Project Manager — create, configure, and manage Foundry agents (CognitiveServices-based)
resource "azurerm_role_assignment" "current_user_ai_project_management" {
  scope              = module.ai_services.ai_account_id
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/eadc314b-1a2d-4efa-be10-5d325db5065e"
  principal_id       = data.azurerm_client_config.current.object_id

  depends_on = [module.ai_services]
}

# Azure AI User — invoke agents and use AI services from the notebook
resource "azurerm_role_assignment" "current_user_ai_user" {
  scope              = module.ai_services.ai_account_id
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/53ca6127-db72-4b80-b1b0-d745d6d5456d"
  principal_id       = data.azurerm_client_config.current.object_id

  depends_on = [module.ai_services]
}

# Cognitive Services OpenAI User — invoke models (GPT-4.1, embeddings)
resource "azurerm_role_assignment" "current_user_openai_user" {
  scope                = module.ai_services.ai_account_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Allow deploying user to write secrets to Key Vault during deployment
resource "azurerm_role_assignment" "current_user_kv_secrets_officer" {
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}