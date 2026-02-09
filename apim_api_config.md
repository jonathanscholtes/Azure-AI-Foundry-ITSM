
resource service_aifoundryapimdev_name_resource 'Microsoft.ApiManagement/service@2024-06-01-preview' = {
  name: service_aifoundryapimdev_name
  location: 'East US 2'
  tags: {
    CreatedAt: '2026-02-09T15:09:47Z'
    CreatedBy: 'Terraform'
    Environment: 'dev'
    ManagedBy: 'Terraform'
    Name: 'aifoundryapimdev'
    Project: 'aifoundry'
  }
  sku: {
    name: 'Developer'
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '/subscriptions/71dcf7f8-6dda-4243-a84c-88833a4d8278/resourcegroups/rg-aifoundry-dev-ewxyl469/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-ai-foundry-main': {
        resourceArmId: null
      }
    }
  }
  properties: {
    publisherEmail: 'admin@aifoundry.com'
    publisherName: 'AI Foundry ITSM'
    notificationSenderEmail: 'apimgmt-noreply@mail.windowsazure.com'
    hostnameConfigurations: [
      {
        type: 'Proxy'
        hostName: '${service_aifoundryapimdev_name}.azure-api.net'
        negotiateClientCertificate: false
        defaultSslBinding: true
        certificateSource: 'BuiltIn'
      }
    ]
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_128_CBC_SHA': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_128_CBC_SHA256': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_128_GCM_SHA256': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_256_CBC_SHA': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_256_CBC_SHA256': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_256_GCM_SHA384': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Protocols.Server.Http2': 'False'
    }
    virtualNetworkType: 'None'
    certificates: []
    disableGateway: false
    natGatewayState: 'Unsupported'
    apiVersionConstraint: {}
    publicNetworkAccess: 'Enabled'
    legacyPortalStatus: 'Disabled'
    developerPortalStatus: 'Enabled'
    releaseChannel: 'Preview'
  }
}

resource service_aifoundryapimdev_name_halo_itsm 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
  parent: service_aifoundryapimdev_name_resource
  name: 'halo-itsm'
  properties: {
    displayName: 'Halo ITSM'
    apiRevision: '1'
    description: 'Use this server to interact with Halo ITSM. It provides tools to search and retrieve official knowledge base articles and access service desk data for IT support and incident‑response workflows.'
    subscriptionRequired: false
    path: 'halo-itsm'
    protocols: [
      'https'
    ]
    authenticationSettings: {
      oAuth2AuthenticationSettings: []
      openidAuthenticationSettings: []
    }
    subscriptionKeyParameterNames: {
      header: 'Ocp-Apim-Subscription-Key'
      query: 'subscription-key'
    }
    type: 'mcp'
    isCurrent: true
  }
}

resource service_aifoundryapimdev_name_halo_itsm_api 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
  parent: service_aifoundryapimdev_name_resource
  name: 'halo-itsm-api'
  properties: {
    displayName: 'Halo ITSM API'
    apiRevision: '1'
    subscriptionRequired: true
    serviceUrl: 'https://scholtes.haloitsm.com/api'
    path: 'halo'
    protocols: [
      'https'
    ]
    authenticationSettings: {
      oAuth2AuthenticationSettings: []
      openidAuthenticationSettings: []
    }
    subscriptionKeyParameterNames: {
      header: 'Ocp-Apim-Subscription-Key'
      query: 'subscription-key'
    }
    isCurrent: true
  }
}


resource service_aifoundryapimdev_name_halo_itsm_api_knowledgebase 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: service_aifoundryapimdev_name_halo_itsm_api
  name: 'knowledgebase'
  properties: {
    displayName: 'knowledgebase'
    method: 'GET'
    urlTemplate: '/KBArticle'
    templateParameters: []
    responses: []
  }
  dependsOn: [
    service_aifoundryapimdev_name_resource
  ]
}

resource service_aifoundryapimdev_name_halo_itsm_api_knowledgebase_by_id 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: service_aifoundryapimdev_name_halo_itsm_api
  name: 'knowledgebase-by-id'
  properties: {
    displayName: 'knowledgebase by id'
    method: 'GET'
    urlTemplate: '/KBArticle/{id}'
    templateParameters: [
      {
        name: 'id'
        required: true
        values: []
        type: operations_knowledgebase_by_id_type
      }
    ]
    responses: []
  }
  dependsOn: [
    service_aifoundryapimdev_name_resource
  ]
}

resource service_aifoundryapimdev_name_halo_itsm_policy 'Microsoft.ApiManagement/service/apis/policies@2024-06-01-preview' = {
  parent: service_aifoundryapimdev_name_halo_itsm
  name: 'policy'
  properties: {
    value: '<!--\r\n    - Policies are applied in the order they appear.\r\n    - Position <base/> inside a section to inherit policies from the outer scope.\r\n    - Comments within policies are not preserved.\r\n-->\r\n<!-- Add policies as children to the <inbound>, <outbound>, <backend>, and <on-error> elements -->\r\n<policies>\r\n  <!-- Throttle, authorize, validate, cache, or transform the requests -->\r\n  <inbound></inbound>\r\n  <!-- Control if and how the requests are forwarded to services  -->\r\n  <backend>\r\n    <base />\r\n  </backend>\r\n  <!-- Customize the responses -->\r\n  <outbound></outbound>\r\n  <!-- Handle exceptions and customize error responses  -->\r\n  <on-error>\r\n    <base />\r\n  </on-error>\r\n</policies>'
    format: 'xml'
  }
  dependsOn: [
    service_aifoundryapimdev_name_resource
  ]
}

resource service_aifoundryapimdev_name_halo_itsm_api_policy 'Microsoft.ApiManagement/service/apis/policies@2024-06-01-preview' = {
  parent: service_aifoundryapimdev_name_halo_itsm_api
  name: 'policy'
  properties: {
    value: '<!--\r\n    - Policies are applied in the order they appear.\r\n    - Position <base/> inside a section to inherit policies from the outer scope.\r\n    - Comments within policies are not preserved.\r\n-->\r\n<!-- Add policies as children to the <inbound>, <outbound>, <backend>, and <on-error> elements -->\r\n<policies>\r\n  <!-- Throttle, authorize, validate, cache, or transform the requests -->\r\n  <inbound>\r\n    <base />\r\n    <set-header name="X-Halo-Api-Key" exists-action="override">\r\n      <value>{{halo-api-key}}</value>\r\n    </set-header>\r\n  </inbound>\r\n  <!-- Control if and how the requests are forwarded to services  -->\r\n  <backend>\r\n    <base />\r\n  </backend>\r\n  <!-- Customize the responses -->\r\n  <outbound>\r\n    <base />\r\n  </outbound>\r\n  <!-- Handle exceptions and customize error responses  -->\r\n  <on-error>\r\n    <base />\r\n  </on-error>\r\n</policies>'
    format: 'xml'
  }
  dependsOn: [
    service_aifoundryapimdev_name_resource
  ]
}


resource service_aifoundryapimdev_name_kb_698a37011696c5955bf3514a 'Microsoft.ApiManagement/service/tags@2024-06-01-preview' = {
  parent: service_aifoundryapimdev_name_resource
  name: 'kb-698a37011696c5955bf3514a'
  properties: {
    displayName: 'KB'
  }
}

resource service_aifoundryapimdev_name_halo_itsm_api_knowledgebase_kb_698a37011696c5955bf3514a 'Microsoft.ApiManagement/service/apis/operations/tags@2024-06-01-preview' = {
  parent: service_aifoundryapimdev_name_halo_itsm_api_knowledgebase
  name: 'kb-698a37011696c5955bf3514a'
  dependsOn: [
    service_aifoundryapimdev_name_halo_itsm_api
    service_aifoundryapimdev_name_resource
  ]
}

resource service_aifoundryapimdev_name_halo_itsm_api_knowledgebase_by_id_kb_698a37011696c5955bf3514a 'Microsoft.ApiManagement/service/apis/operations/tags@2024-06-01-preview' = {
  parent: service_aifoundryapimdev_name_halo_itsm_api_knowledgebase_by_id
  name: 'kb-698a37011696c5955bf3514a'
  dependsOn: [
    service_aifoundryapimdev_name_halo_itsm_api
    service_aifoundryapimdev_name_resource
  ]
}

resource service_aifoundryapimdev_name_kb_698a37011696c5955bf3514a_698a3708217d200cac61b0e1 'Microsoft.ApiManagement/service/tags/operationLinks@2024-06-01-preview' = {
  parent: service_aifoundryapimdev_name_kb_698a37011696c5955bf3514a
  name: '698a3708217d200cac61b0e1'
  properties: {
    operationId: service_aifoundryapimdev_name_halo_itsm_api_knowledgebase_by_id.id
  }
  dependsOn: [
    service_aifoundryapimdev_name_resource
  ]
}

resource service_aifoundryapimdev_name_kb_698a37011696c5955bf3514a_698a3711217d200cac61b0e3 'Microsoft.ApiManagement/service/tags/operationLinks@2024-06-01-preview' = {
  parent: service_aifoundryapimdev_name_kb_698a37011696c5955bf3514a
  name: '698a3711217d200cac61b0e3'
  properties: {
    operationId: service_aifoundryapimdev_name_halo_itsm_api_knowledgebase.id
  }
  dependsOn: [
    service_aifoundryapimdev_name_resource
  ]
}