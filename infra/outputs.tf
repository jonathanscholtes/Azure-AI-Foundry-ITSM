output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "container_registry_id" {
  description = "ID of the container registry"
  value       = azurerm_container_registry.main.id
}

output "container_registry_login_server" {
  description = "Login server of the container registry"
  value       = azurerm_container_registry.main.login_server
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "search_service_id" {
  description = "ID of the AI Search service"
  value       = azurerm_search_service.main.id
}

output "search_service_name" {
  description = "Name of the AI Search service"
  value       = azurerm_search_service.main.name
}

output "search_service_endpoint" {
  description = "Endpoint of the AI Search service"
  value       = "https://${azurerm_search_service.main.name}.search.windows.net"
}

output "apim_id" {
  description = "ID of the API Management service"
  value       = azurerm_api_management.main.id
}

output "apim_name" {
  description = "Name of the API Management service"
  value       = azurerm_api_management.main.name
}

output "apim_gateway_url" {
  description = "Gateway URL of the API Management service"
  value       = azurerm_api_management.main.gateway_url
}

output "apim_management_api_url" {
  description = "Management API URL of the API Management service"
  value       = azurerm_api_management.main.management_api_url
}

output "apim_portal_url" {
  description = "Portal URL of the API Management service"
  value       = azurerm_api_management.main.portal_url
}

# AI Foundry Outputs
output "ai_account_id" {
  description = "ID of the AI Services account"
  value       = azapi_resource.ai_account.id
}

output "ai_account_endpoint" {
  description = "Endpoint of the AI Services account"
  value       = azapi_resource.ai_account.output.properties.endpoint
}

output "ai_account_name" {
  description = "Name of the AI Services account"
  value       = local.ai_account_name
}

output "openai_endpoint" {
  description = "OpenAI endpoint for the AI Services account"
  value       = "https://${local.ai_account_name}.cognitiveservices.azure.com/"
}

output "ai_project_id" {
  description = "ID of the AI Project"
  value       = azapi_resource.ai_project.id
}

output "ai_project_name" {
  description = "Name of the AI Project"
  value       = local.ai_project_name
}

output "ai_project_endpoint" {
  description = "Endpoint of the AI Project"
  value       = azapi_resource.ai_project.output.properties.endpoints["AI Foundry API"]
}

output "managed_identity_id" {
  description = "ID of the user-assigned managed identity for all services"
  value       = azurerm_user_assigned_identity.main.id
}

output "managed_identity_principal_id" {
  description = "Principal ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.main.principal_id
}

output "app_insights_id" {
  description = "ID of Application Insights"
  value       = azurerm_application_insights.ai_foundry.id
}

output "app_insights_name" {
  description = "Name of Application Insights"
  value       = azurerm_application_insights.ai_foundry.name
}

output "app_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.ai_foundry.connection_string
  sensitive   = true
}
