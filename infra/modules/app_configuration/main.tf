resource "azurerm_app_configuration" "main" {
  name                = var.app_configuration_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "free"

  tags = var.tags
}

# Managed identity gets read-only access (container apps read agent config at startup)
resource "azurerm_role_assignment" "data_reader" {
  scope                = azurerm_app_configuration.main.id
  role_definition_name = "App Configuration Data Reader"
  principal_id         = var.identity_principal_id
}

# Deploying user/SP gets read-write access (deploy scripts write agent IDs)
resource "azurerm_role_assignment" "data_owner" {
  scope                = azurerm_app_configuration.main.id
  role_definition_name = "App Configuration Data Owner"
  principal_id         = var.deployer_principal_id
}
