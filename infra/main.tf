# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = merge(
    var.tags,
    {
      Name = var.resource_group_name
    }
  )
}

# Storage Account (required for AI Hub)
resource "azurerm_storage_account" "main" {
  name                     = replace(var.storage_account_name, "-", "")
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  shared_access_key_enabled = false
  https_traffic_only_enabled = true

  tags = merge(
    var.tags,
    {
      Name = var.storage_account_name
    }
  )
}

# Grant Storage Blob Data Contributor role to managed identity
resource "azurerm_role_assignment" "storage_blob_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.main.principal_id

  depends_on = [azurerm_storage_account.main, azurerm_user_assigned_identity.main]
}

# Grant Storage Account Contributor role to managed identity
resource "azurerm_role_assignment" "storage_account_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azurerm_user_assigned_identity.main.principal_id

  depends_on = [azurerm_storage_account.main, azurerm_user_assigned_identity.main]
}

# Container Registry (optional but recommended for AI Foundry)
resource "azurerm_container_registry" "main" {
  name                = replace(var.container_registry_name, "-", "")
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.container_registry_sku
  admin_enabled       = true

  tags = merge(
    var.tags,
    {
      Name = var.container_registry_name
    }
  )
}

# Key Vault (required for AI Hub)
resource "azurerm_key_vault" "main" {
  name                = replace(var.key_vault_name, "-", "")
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  purge_protection_enabled = var.enable_purge_protection
  soft_delete_retention_days = 7

  tags = merge(
    var.tags,
    {
      Name = var.key_vault_name
    }
  )
}

# Grant Key Vault Secrets User role to managed identity
resource "azurerm_role_assignment" "keyvault_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.main.principal_id

  depends_on = [azurerm_key_vault.main, azurerm_user_assigned_identity.main]
}

# Grant Key Vault Crypto User role to managed identity
resource "azurerm_role_assignment" "keyvault_crypto_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = azurerm_user_assigned_identity.main.principal_id

  depends_on = [azurerm_key_vault.main, azurerm_user_assigned_identity.main]
}

# AI Search Service
resource "azurerm_search_service" "main" {
  name                = var.search_service_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.search_sku

  tags = merge(
    var.tags,
    {
      Name = var.search_service_name
    }
  )

  depends_on = [azurerm_resource_group.main]
}

# Grant Search Service Contributor role to managed identity
resource "azurerm_role_assignment" "search_service_contributor" {
  scope                = azurerm_search_service.main.id
  role_definition_name = "Search Service Contributor"
  principal_id         = azurerm_user_assigned_identity.main.principal_id

  depends_on = [azurerm_search_service.main, azurerm_user_assigned_identity.main]
}

# Grant Search Index Data Contributor role to managed identity
resource "azurerm_role_assignment" "search_index_data_contributor" {
  scope                = azurerm_search_service.main.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = azurerm_user_assigned_identity.main.principal_id

  depends_on = [azurerm_search_service.main, azurerm_user_assigned_identity.main]
}

# API Management Service
resource "azurerm_api_management" "main" {
  name                = "${var.project_name}apim${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  publisher_name      = var.apim_publisher_name
  publisher_email     = var.apim_publisher_email
  sku_name            = var.apim_sku == "Consumption" ? "Consumption" : "${var.apim_sku}_${var.apim_sku_capacity}"
  client_certificate_enabled = false

  identity {
    type = "SystemAssigned"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-apim"
    }
  )

  depends_on = [azurerm_resource_group.main]
  
  # Add timeout to handle slow provisioning
  timeouts {
    create = "60m"
    delete = "30m"
  }
}

# Data source for current Azure context
data "azurerm_client_config" "current" {}

# User-Assigned Managed Identity (shared across all services)
resource "azurerm_user_assigned_identity" "main" {
  name                = var.managed_identity_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = merge(
    var.tags,
    {
      Name = var.managed_identity_name
    }
  )
}

# Application Insights
resource "azurerm_application_insights" "ai_foundry" {
  name                = var.app_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"

  tags = merge(
    var.tags,
    {
      Name = var.app_insights_name
    }
  )
}

# AI Services Account (Microsoft Foundry)
resource "azapi_resource" "ai_account" {
  type      = "Microsoft.CognitiveServices/accounts@2025-06-01"
  name      = local.ai_account_name
  location  = azurerm_resource_group.main.location
  parent_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.main.id]
  }

  body = {
    kind = "AIServices"
    properties = {
      apiProperties      = {}
      customSubDomainName = local.ai_account_name
      networkAcls = {
        defaultAction         = "Allow"
        virtualNetworkRules   = []
        ipRules               = []
      }
      allowProjectManagement = true
      publicNetworkAccess    = "Enabled"
      disableLocalAuth       = false
    }
    sku = {
      name = "S0"
    }
    tags = {
      "SecurityControl" = "ignore"
    }
  }

  depends_on = [azurerm_resource_group.main, azurerm_user_assigned_identity.main]
}

# Deploy GPT-4o model
resource "azapi_resource" "gpt4o_deployment" {
  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-06-01"
  name      = "gpt-4o"
  parent_id = azapi_resource.ai_account.id

  body = {
    sku = {
      name     = "Standard"
      capacity = var.ai_services_deployment_gpt4o_capacity
    }
    properties = {
      model = {
        format  = "OpenAI"
        name    = "gpt-4o"
        version = "2024-08-06"
      }
      versionUpgradeOption = "OnceNewDefaultVersionAvailable"
    }
  }

  depends_on = [azapi_resource.ai_account]
}

# Deploy text-embedding-ada-002 model
resource "azapi_resource" "embedding_deployment" {
  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-06-01"
  name      = "text-embedding-ada-002"
  parent_id = azapi_resource.ai_account.id

  body = {
    sku = {
      name     = "Standard"
      capacity = var.ai_services_deployment_embedding_capacity
    }
    properties = {
      model = {
        format  = "OpenAI"
        name    = "text-embedding-ada-002"
        version = "2"
      }
      versionUpgradeOption = "OnceNewDefaultVersionAvailable"
    }
  }

  depends_on = [azapi_resource.gpt4o_deployment]
}

# AI Project
resource "azapi_resource" "ai_project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  name      = local.ai_project_name
  location  = azurerm_resource_group.main.location
  parent_id = azapi_resource.ai_account.id

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {}
  }

  depends_on = [
    azapi_resource.ai_account,
    azapi_resource.gpt4o_deployment,
    azapi_resource.embedding_deployment
  ]
}

# Grant Cognitive Services OpenAI User role to managed identity
resource "azurerm_role_assignment" "openai_user" {
  scope                = azapi_resource.ai_account.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.main.principal_id

  depends_on = [azapi_resource.ai_account, azurerm_user_assigned_identity.main]
}

# Grant Cognitive Services User role to managed identity
resource "azurerm_role_assignment" "cognitive_services_user" {
  scope                = azapi_resource.ai_account.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_user_assigned_identity.main.principal_id

  depends_on = [azapi_resource.ai_account, azurerm_user_assigned_identity.main]
}
