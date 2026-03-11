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
# APIs (azapi - uses ARM directly, bypasses APIM management endpoint)
# ================================================

resource "azapi_resource" "halo_http_api" {
  type      = "Microsoft.ApiManagement/service/apis@2022-08-01"
  name      = "halo-itsm-api"
  parent_id = azurerm_api_management.main.id

  body = {
    properties = {
      displayName          = "Halo ITSM API"
      description          = "Proxies requests to the Halo ITSM instance. Injects the Halo API key from Key Vault via a named value so callers never handle credentials directly."
      serviceUrl           = var.halo_base_url
      path                 = "halo"
      protocols            = ["https"]
      subscriptionRequired = false
      apiRevision          = "1"
      subscriptionKeyParameterNames = {
        header = "Ocp-Apim-Subscription-Key"
        query  = "subscription-key"
      }
    }
  }
}

# ================================================
# API Policies (azapi)
# ================================================

# HTTP API Policy - only applied once the Named Value (KV secret) exists
resource "azapi_resource" "halo_http_policy" {
  count     = var.key_vault_secret_identifier != null ? 1 : 0
  type      = "Microsoft.ApiManagement/service/apis/policies@2022-08-01"
  name      = "policy"
  parent_id = azapi_resource.halo_http_api.id

  body = {
    properties = {
      format = "xml"
      value  = <<-XML
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
    }
  }

  depends_on = [azapi_resource.halo_api_key_named_value]
}

# ================================================
# API Operations (azapi)
# ================================================

# Knowledgebase GET operation
resource "azapi_resource" "knowledgebase_operation" {
  type      = "Microsoft.ApiManagement/service/apis/operations@2022-08-01"
  name      = "knowledgebase"
  parent_id = azapi_resource.halo_http_api.id

  body = {
    properties = {
      displayName = "knowledgebase"
      description = "Search and list knowledge base articles from the Halo ITSM knowledge base. Pass the 'search' parameter to filter results by keyword rather than retrieving all articles."
      method      = "GET"
      urlTemplate = "/KBArticle"
      request = {
        queryParameters = [
          {
            name        = "search"
            required    = false
            type        = "string"
            description = "Filter articles by keyword. Always supply this to narrow results before fetching full article content."
          },
          {
            name        = "count"
            required    = false
            type        = "integer"
            description = "Maximum number of articles to return. Use to limit result size."
          },
          {
            name        = "pageinate"
            required    = false
            type        = "boolean"
            description = "Whether to use pagination in the response."
          },
          {
            name        = "page_size"
            required    = false
            type        = "integer"
            description = "Number of results per page when using pagination."
          },
          {
            name        = "page_no"
            required    = false
            type        = "integer"
            description = "Page number to return when using pagination."
          }
        ]
      }
      responses = [
        {
          statusCode  = 200
          description = "Array of knowledge base article objects"
        }
      ]
    }
  }
}

# Knowledgebase by ID GET operation
resource "azapi_resource" "knowledgebase_by_id_operation" {
  type      = "Microsoft.ApiManagement/service/apis/operations@2022-08-01"
  name      = "knowledgebase-by-id"
  parent_id = azapi_resource.halo_http_api.id

  body = {
    properties = {
      displayName        = "knowledgebasebyid"
      description        = "Retrieves the full content of a single knowledge base article by its Halo ITSM article ID. Use 'includedetails=true' to ensure the complete article body is returned."
      method             = "GET"
      urlTemplate        = "/KBArticle/{id}"
      templateParameters = [
        {
          name        = "id"
          required    = true
          type        = "integer"
          description = "Halo ITSM knowledge base article ID"
        }
      ]
      request = {
        queryParameters = [
          {
            name        = "includedetails"
            required    = false
            type        = "boolean"
            description = "Set to true to include the full article body and all associated detail objects. Always pass true when retrieving an article for display."
          }
        ]
      }
      responses = [
        {
          statusCode  = 200
          description = "Knowledge base article object"
        },
        {
          statusCode  = 404
          description = "Article not found"
        }
      ]
    }
  }
}

# ================================================
# Tags (azapi)
# ================================================

resource "azapi_resource" "kb_tag" {
  type      = "Microsoft.ApiManagement/service/tags@2022-08-01"
  name      = "kb"
  parent_id = azurerm_api_management.main.id

  body = {
    properties = {
      displayName = "KB"
    }
  }
}

# ================================================
# Operation Tags (azapi)
# ================================================

# Link knowledgebase operation to KB tag
resource "azapi_resource" "knowledgebase_kb_tag" {
  type      = "Microsoft.ApiManagement/service/apis/operations/tags@2022-08-01"
  name      = "kb"
  parent_id = azapi_resource.knowledgebase_operation.id

  body = {}

  depends_on = [azapi_resource.kb_tag]
}

# Link knowledgebase_by_id operation to KB tag
resource "azapi_resource" "knowledgebase_by_id_kb_tag" {
  type      = "Microsoft.ApiManagement/service/apis/operations/tags@2022-08-01"
  name      = "kb"
  parent_id = azapi_resource.knowledgebase_by_id_operation.id

  body = {}

  depends_on = [azapi_resource.kb_tag]
}

# ================================================
# Named Values (azapi)
# ================================================

# Halo API Key Named Value - created after secret is pushed to Key Vault
resource "azapi_resource" "halo_api_key_named_value" {
  count     = var.key_vault_secret_identifier != null ? 1 : 0
  type      = "Microsoft.ApiManagement/service/namedValues@2022-08-01"
  name      = "halo-api-key"
  parent_id = azurerm_api_management.main.id

  body = {
    properties = {
      displayName = "halo-api-key"
      secret      = true
      keyVault = {
        secretIdentifier = var.key_vault_secret_identifier
        identityClientId = var.identity_client_id
      }
    }
  }
}
