terraform {
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }
}

resource "azurerm_api_management" "main" {
  name                = var.apim_name
  location            = var.location
  resource_group_name = var.resource_group_name
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = var.apim_sku == "Consumption" ? "Consumption" : "${var.apim_sku}_${var.apim_sku_capacity}"
  client_certificate_enabled = false

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [var.managed_identity_id]
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

# ================================================
# APIs
# ================================================

# Halo ITSM MCP API - Using azapi to access preview API with MCP type support
resource "azapi_resource" "halo_mcp" {
  type      = "Microsoft.ApiManagement/service/apis@2024-06-01-preview"
  name      = "halo-itsm"
  parent_id = azurerm_api_management.main.id

  body = {
    properties = {
      displayName        = "Halo ITSM MCP"
      apiRevision        = "1"
      description        = "Use this server to interact with Halo ITSM. It provides tools to search and retrieve official knowledge base articles and access service desk data for IT support and incident-response workflows."
      subscriptionRequired = false
      path               = "halo-itsm"
      protocols          = ["https"]
      type               = "mcp"
      isCurrent          = true
      authenticationSettings = {
        oAuth2AuthenticationSettings = []
        openidAuthenticationSettings = []
      }
      subscriptionKeyParameterNames = {
        header = "Ocp-Apim-Subscription-Key"
        query  = "subscription-key"
      }
    }
  }

  depends_on = [azurerm_api_management.main]
}

# Halo ITSM HTTP API
resource "azurerm_api_management_api" "halo_http" {
  name                = "halo-itsm-api"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.main.name
  revision            = "1"
  display_name        = "Halo ITSM API"
  service_url         = "https://scholtes.haloitsm.com/api"
  path                = "halo"
  protocols           = ["https"]
  subscription_required = true

  subscription_key_parameter_names {
    header = "Ocp-Apim-Subscription-Key"
    query  = "subscription-key"
  }

  depends_on = [azurerm_api_management.main]
}

# ================================================
# API Policies
# ================================================

# MCP API Policy
resource "azapi_resource" "halo_mcp_policy" {
  type      = "Microsoft.ApiManagement/service/apis/policies@2024-06-01-preview"
  name      = "policy"
  parent_id = azapi_resource.halo_mcp.id

  body = {
    properties = {
      value  = <<-XML
        <!--
            - Policies are applied in the order they appear.
            - Position <base/> inside a section to inherit policies from the outer scope.
            - Comments within policies are not preserved.
        -->
        <!-- Add policies as children to the <inbound>, <outbound>, <backend>, and <on-error> elements -->
        <policies>
          <!-- Throttle, authorize, validate, cache, or transform the requests -->
          <inbound></inbound>
          <!-- Control if and how the requests are forwarded to services  -->
          <backend>
            <base />
          </backend>
          <!-- Customize the responses -->
          <outbound></outbound>
          <!-- Handle exceptions and customize error responses  -->
          <on-error>
            <base />
          </on-error>
        </policies>
      XML
      format = "xml"
    }
  }

  depends_on = [azapi_resource.halo_mcp]
}

# HTTP API Policy
resource "azurerm_api_management_api_policy" "halo_http_policy" {
  api_name            = azurerm_api_management_api.halo_http.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = var.resource_group_name

  xml_content = <<-XML
    <policies>
      <inbound>
        <base />
        <set-header name="X-Halo-Api-Key" exists-action="override">
          <value>{{halo-api-key}}</value>
        </set-header>
      </inbound>
      <backend>
        <base />
      </backend>
      <outbound>
        <base />
      </outbound>
      <on-error>
        <base />
      </on-error>
    </policies>
  XML

  depends_on = [azurerm_api_management_named_value.halo_api_key]
}

# ================================================
# API Operations
# ================================================

# Knowledgebase GET operation
resource "azurerm_api_management_api_operation" "knowledgebase" {
  operation_id        = "knowledgebase"
  api_name            = azurerm_api_management_api.halo_http.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = var.resource_group_name
  display_name        = "knowledgebase"
  method              = "GET"
  url_template        = "/KBArticle"
}

# Knowledgebase by ID GET operation
resource "azurerm_api_management_api_operation" "knowledgebase_by_id" {
  operation_id        = "knowledgebase-by-id"
  api_name            = azurerm_api_management_api.halo_http.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = var.resource_group_name
  display_name        = "knowledgebase by id"
  method              = "GET"
  url_template        = "/KBArticle/{id}"

  template_parameter {
    name        = "id"
    required    = true
    type        = "string"
  }
}

# ================================================
# Tags
# ================================================

# KB Tag
resource "azurerm_api_management_tag" "kb" {
  api_management_id = azurerm_api_management.main.id
  name              = "kb"
  display_name      = "KB"
}

# ================================================
# Operation Tags
# ================================================

# Link knowledgebase operation to KB tag
resource "azurerm_api_management_api_operation_tag" "knowledgebase_kb" {
  api_operation_id = azurerm_api_management_api_operation.knowledgebase.id
  name             = azurerm_api_management_tag.kb.name
  display_name     = azurerm_api_management_tag.kb.display_name
}

# Link knowledgebase_by_id operation to KB tag
resource "azurerm_api_management_api_operation_tag" "knowledgebase_by_id_kb" {
  api_operation_id = azurerm_api_management_api_operation.knowledgebase_by_id.id
  name             = azurerm_api_management_tag.kb.name
  display_name     = azurerm_api_management_tag.kb.display_name
}

# ================================================
# Named Values
# ================================================

# Halo API Key Named Value - created after secret is pushed to Key Vault
resource "azurerm_api_management_named_value" "halo_api_key" {
  count               = var.key_vault_secret_identifier != null ? 1 : 0
  name                = "halo-api-key"
  api_management_name = azurerm_api_management.main.name
  resource_group_name = var.resource_group_name
  display_name        = "halo-api-key"
  secret              = true

  value_from_key_vault {
    secret_id          = var.key_vault_secret_identifier
    identity_client_id = var.identity_client_id
  }
}
