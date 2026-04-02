output "id" {
  description = "ID of the App Configuration store"
  value       = azurerm_app_configuration.main.id
}

output "endpoint" {
  description = "Endpoint of the App Configuration store"
  value       = azurerm_app_configuration.main.endpoint
}

output "name" {
  description = "Name of the App Configuration store"
  value       = azurerm_app_configuration.main.name
}
