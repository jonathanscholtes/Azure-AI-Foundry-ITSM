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
      subscriptionRequired = true
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

# HTTP API Policy - API Key mode (only when auth_method is 'apikey' and Named Value exists)
resource "azapi_resource" "halo_http_policy" {
  count     = var.halo_auth_method == "apikey" && var.key_vault_secret_identifier != null ? 1 : 0
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
            <set-query-parameter name="count" exists-action="skip">
              <value>5</value>
            </set-query-parameter>
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

# HTTP API Policy - OAuth mode (only when auth_method is 'oauth' and Named Values exist)
resource "azapi_resource" "halo_http_policy_oauth" {
  count     = var.halo_auth_method == "oauth" && var.halo_client_id_secret_identifier != null ? 1 : 0
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
            <set-query-parameter name="count" exists-action="skip">
              <value>5</value>
            </set-query-parameter>
            <!-- Resolve Key Vault-backed named values into context variables -->
            <set-variable name="haloClientId" value="{{halo-client-id}}" />
            <set-variable name="haloClientSecret" value="{{halo-client-secret}}" />
            <set-variable name="haloAuthUrl" value="{{halo-auth-url}}" />
            <!-- Check cache for existing bearer token -->
            <cache-lookup-value key="halo-bearer-token" variable-name="bearerToken" />
            <choose>
              <when condition="@(!context.Variables.ContainsKey(&quot;bearerToken&quot;))">
                <!-- Acquire token from Halo OAuth endpoint -->
                <send-request mode="new" response-variable-name="tokenResponse" timeout="20" ignore-error="false">
                  <set-url>@((string)context.Variables["haloAuthUrl"])</set-url>
                  <set-method>POST</set-method>
                  <set-header name="Content-Type" exists-action="override">
                    <value>application/x-www-form-urlencoded</value>
                  </set-header>
                  <set-header name="Authorization" exists-action="override">
                    <value>@{
                      var clientId = (string)context.Variables["haloClientId"];
                      var clientSecret = (string)context.Variables["haloClientSecret"];
                      return "Basic " + Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes($"{clientId}:{clientSecret}"));
                    }</value>
                  </set-header>
                  <set-body>grant_type=client_credentials&amp;scope=all</set-body>
                </send-request>
                <!-- Parse and cache the token (3500s = just under 1h expiry) -->
                <set-variable name="bearerToken" value="@(((IResponse)context.Variables[&quot;tokenResponse&quot;]).Body.As&lt;JObject&gt;()[&quot;access_token&quot;].ToString())" />
                <cache-store-value key="halo-bearer-token" value="@((string)context.Variables[&quot;bearerToken&quot;])" duration="3500" />
              </when>
            </choose>
            <set-header name="Authorization" exists-action="override">
              <value>@($"Bearer {(string)context.Variables[&quot;bearerToken&quot;]}")</value>
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

  depends_on = [azapi_resource.halo_client_id_named_value, azapi_resource.halo_client_secret_named_value, azapi_resource.halo_auth_url_named_value]
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
            defaultValue = "5"
            description = "Maximum number of articles to return (default: 5). Use to limit result size."
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
# Ticket Operations (azapi)
# ================================================

# Tickets list GET operation
resource "azapi_resource" "tickets_operation" {
  type      = "Microsoft.ApiManagement/service/apis/operations@2022-08-01"
  name      = "tickets"
  parent_id = azapi_resource.halo_http_api.id

  body = {
    properties = {
      displayName = "tickets"
      description = "List and search tickets from Halo ITSM. Returns a paginated list of ticket objects."
      method      = "GET"
      urlTemplate = "/Tickets"
      request = {
        queryParameters = [
          {
            name         = "page_no"
            required     = false
            type         = "integer"
            description  = "Page number to return when using pagination."
          },
          {
            name         = "page_size"
            required     = false
            type         = "integer"
            description  = "Number of results per page when using pagination."
          },
          {
            name         = "search"
            required     = false
            type         = "string"
            description  = "Filter tickets by keyword."
          },
          {
            name         = "ticketidonly"
            required     = false
            type         = "boolean"
            description  = "Returns only the ID fields (Ticket ID, SLA ID, Status ID, Client ID and Name and Lastincomingemail date) of the Tickets. Not compatible with pagination."
          },
          {
            name         = "count"
            required     = false
            type         = "integer"
            defaultValue = "5"
            description  = "Maximum number of tickets to return (default: 5)."
          }
        ]
      }
      responses = [
        {
          statusCode  = 200
          description = "Paginated list of ticket objects"
        }
      ]
    }
  }
}

# Ticket by ID GET operation
resource "azapi_resource" "tickets_by_id_operation" {
  type      = "Microsoft.ApiManagement/service/apis/operations@2022-08-01"
  name      = "tickets-by-id"
  parent_id = azapi_resource.halo_http_api.id

  body = {
    properties = {
      displayName        = "ticketsbyid"
      description        = "Retrieves a single ticket object by its Halo ITSM ticket ID."
      method             = "GET"
      urlTemplate        = "/Tickets/{id}"
      templateParameters = [
        {
          name        = "id"
          required    = true
          type        = "integer"
          description = "The Ticket's ID"
        }
      ]
      request = {
        queryParameters = [
          {
            name        = "includedetails"
            required    = false
            type        = "boolean"
            description = "Whether to include extra objects in the response."
          },
          {
            name        = "includelastaction"
            required    = false
            type        = "boolean"
            description = "Whether to include the last action in the response."
          },
          {
            name        = "ticketidonly"
            required    = false
            type        = "boolean"
            description = "Returns only the ID fields (Ticket ID, SLA ID, Status ID, Client ID and Name and Lastincomingemail date)."
          }
        ]
      }
      responses = [
        {
          statusCode  = 200
          description = "Single ticket object"
        },
        {
          statusCode  = 404
          description = "Ticket not found"
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

resource "azapi_resource" "tickets_tag" {
  type      = "Microsoft.ApiManagement/service/tags@2022-08-01"
  name      = "tickets"
  parent_id = azurerm_api_management.main.id

  body = {
    properties = {
      displayName = "Tickets"
    }
  }
}

# Link tickets operation to Tickets tag
resource "azapi_resource" "tickets_tickets_tag" {
  type      = "Microsoft.ApiManagement/service/apis/operations/tags@2022-08-01"
  name      = "tickets"
  parent_id = azapi_resource.tickets_operation.id

  body = {}

  depends_on = [azapi_resource.tickets_tag]
}

# Link tickets_by_id operation to Tickets tag
resource "azapi_resource" "tickets_by_id_tickets_tag" {
  type      = "Microsoft.ApiManagement/service/apis/operations/tags@2022-08-01"
  name      = "tickets"
  parent_id = azapi_resource.tickets_by_id_operation.id

  body = {}

  depends_on = [azapi_resource.tickets_tag]
}

# ================================================
# Named Values (azapi)
# ================================================

# Halo API Key Named Value - created after secret is pushed to Key Vault (apikey mode)
resource "azapi_resource" "halo_api_key_named_value" {
  count     = var.halo_auth_method == "apikey" && var.key_vault_secret_identifier != null ? 1 : 0
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

# Halo OAuth Named Values - created after secrets are pushed to Key Vault (oauth mode)
resource "azapi_resource" "halo_client_id_named_value" {
  count     = var.halo_auth_method == "oauth" && var.halo_client_id_secret_identifier != null ? 1 : 0
  type      = "Microsoft.ApiManagement/service/namedValues@2022-08-01"
  name      = "halo-client-id"
  parent_id = azurerm_api_management.main.id

  body = {
    properties = {
      displayName = "halo-client-id"
      secret      = true
      keyVault = {
        secretIdentifier = var.halo_client_id_secret_identifier
        identityClientId = var.identity_client_id
      }
    }
  }
}

resource "azapi_resource" "halo_client_secret_named_value" {
  count     = var.halo_auth_method == "oauth" && var.halo_client_secret_secret_identifier != null ? 1 : 0
  type      = "Microsoft.ApiManagement/service/namedValues@2022-08-01"
  name      = "halo-client-secret"
  parent_id = azurerm_api_management.main.id

  body = {
    properties = {
      displayName = "halo-client-secret"
      secret      = true
      keyVault = {
        secretIdentifier = var.halo_client_secret_secret_identifier
        identityClientId = var.identity_client_id
      }
    }
  }
}

resource "azapi_resource" "halo_auth_url_named_value" {
  count     = var.halo_auth_method == "oauth" && var.halo_auth_url != null ? 1 : 0
  type      = "Microsoft.ApiManagement/service/namedValues@2022-08-01"
  name      = "halo-auth-url"
  parent_id = azurerm_api_management.main.id

  body = {
    properties = {
      displayName = "halo-auth-url"
      secret      = false
      value       = var.halo_auth_url
    }
  }
}

# ================================================
# Subscriptions (for API key authentication)
# ================================================

resource "azapi_resource" "ai_agent_subscription" {
  type      = "Microsoft.ApiManagement/service/subscriptions@2022-08-01"
  name      = "ai-agent-subscription"
  parent_id = azurerm_api_management.main.id

  body = {
    properties = {
      displayName  = "AI Agent Subscription"
      scope        = "${azurerm_api_management.main.id}/apis"
      state        = "active"
      allowTracing = true
    }
  }

  response_export_values = {
    primaryKey = "properties.primaryKey"
  }
}
