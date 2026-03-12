output "id" {
  description = "ID of the AI Search service"
  value       = azurerm_search_service.main.id
}

output "name" {
  description = "Name of the AI Search service"
  value       = azurerm_search_service.main.name
}

output "endpoint" {
  description = "Endpoint of the AI Search service"
  value       = "https://${azurerm_search_service.main.name}.search.windows.net"
}

output "primary_key" {
  description = "Primary admin key of the AI Search service"
  value       = azurerm_search_service.main.primary_key
  sensitive   = true
}
