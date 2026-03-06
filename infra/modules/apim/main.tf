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

resource "azurerm_api_management_api" "halo_http" {
  name                = "halo-itsm-api"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.main.name
  revision            = "1"
  display_name        = "Halo ITSM API"
  description         = "Proxies requests to the Halo ITSM instance. Injects the Halo API key from Key Vault via a named value so callers never handle credentials directly."
  service_url         = var.halo_base_url
  path                = "halo"
  protocols           = ["https"]
  subscription_required = false

  subscription_key_parameter_names {
    header = "Ocp-Apim-Subscription-Key"
    query  = "subscription-key"
  }

  depends_on = [azurerm_api_management.main]
}

# ================================================
# API Policies
# ================================================

# HTTP API Policy - only applied once the Named Value (KV secret) exists
resource "azurerm_api_management_api_policy" "halo_http_policy" {
  count               = var.key_vault_secret_identifier != null ? 1 : 0
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
  description         = "Search and list knowledge base articles from the Halo ITSM knowledge base. Pass the 'search' parameter to filter results by keyword rather than retrieving all articles."
  method              = "GET"
  url_template        = "/KBArticle"

  request {
    query_parameter {
      name        = "search"
      required    = false
      type        = "string"
      description = "Filter articles by keyword. Always supply this to narrow results before fetching full article content."
    }
    query_parameter {
      name        = "count"
      required    = false
      type        = "integer"
      description = "Maximum number of articles to return. Use to limit result size."
    }
    query_parameter {
      name        = "pageinate"
      required    = false
      type        = "boolean"
      description = "Whether to use pagination in the response."
    }
    query_parameter {
      name        = "page_size"
      required    = false
      type        = "integer"
      description = "Number of results per page when using pagination."
    }
    query_parameter {
      name        = "page_no"
      required    = false
      type        = "integer"
      description = "Page number to return when using pagination."
    }
  }

  response {
    status_code = 200
    description = "Array of knowledge base article objects"
  }
}

# Knowledgebase by ID GET operation
resource "azurerm_api_management_api_operation" "knowledgebase_by_id" {
  operation_id        = "knowledgebase-by-id"
  api_name            = azurerm_api_management_api.halo_http.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = var.resource_group_name
  display_name        = "knowledgebasebyid"
  description         = "Retrieves the full content of a single knowledge base article by its Halo ITSM article ID. Use 'includedetails=true' to ensure the complete article body is returned."
  method              = "GET"
  url_template        = "/KBArticle/{id}"

  template_parameter {
    name        = "id"
    required    = true
    type        = "integer"
    description = "Halo ITSM knowledge base article ID"
  }

  request {
    query_parameter {
      name        = "includedetails"
      required    = false
      type        = "boolean"
      description = "Set to true to include the full article body and all associated detail objects. Always pass true when retrieving an article for display."
    }
  }

  response {
    status_code = 200
    description = "Knowledge base article object"
  }

  response {
    status_code = 404
    description = "Article not found"
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
