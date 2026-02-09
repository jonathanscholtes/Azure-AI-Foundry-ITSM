resource "azurerm_api_management" "main" {
  name                = var.apim_name
  location            = var.location
  resource_group_name = var.resource_group_name
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = var.apim_sku == "Consumption" ? "Consumption" : "${var.apim_sku}_${var.apim_sku_capacity}"
  client_certificate_enabled = false

  identity {
    type = "SystemAssigned"
  }

  tags = merge(
    var.tags,
    {
      Name = var.apim_name
    }
  )

  timeouts {
    create = "120m"
    delete = "60m"
    update = "120m"
  }
}
