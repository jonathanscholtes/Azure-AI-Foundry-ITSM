# Manual Deployment Guide — Microsoft Foundry ITSM

This document describes every Azure resource in the solution, its exact configuration settings, role assignments, and post-deployment steps required when deploying manually (without running `deploy.ps1` / Terraform).

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Resource Group](#2-resource-group)
3. [User-Assigned Managed Identity](#3-user-assigned-managed-identity)
4. [Storage Account](#4-storage-account)
5. [Key Vault](#5-key-vault)
6. [Azure Container Registry](#6-azure-container-registry)
7. [Azure AI Search](#7-azure-ai-search)
8. [Application Insights](#8-application-insights)
9. [API Management](#9-api-management)
10. [Microsoft Foundry — AI Services Account](#10-microsoft-foundry--ai-services-account)
11. [Microsoft Foundry — Model Deployments](#11-microsoft-foundry--model-deployments)
12. [Microsoft Foundry — Project](#12-microsoft-foundry--project)
13. [Microsoft Foundry — Project Connections](#13-microsoft-foundry--project-connections)
14. [Role Assignments Summary](#14-role-assignments-summary)
15. [Post-Deployment: Push Halo API Key to Key Vault](#15-post-deployment-push-halo-api-key-to-key-vault)
16. [Post-Deployment: Configure APIM Named Value](#16-post-deployment-configure-apim-named-value)
17. [Post-Deployment: Create Foundry Agent via Notebook](#17-post-deployment-create-foundry-agent-via-notebook)
18. [Naming Conventions](#18-naming-conventions)
19. [Common Tags](#19-common-tags)

---

## 1. Prerequisites

| Requirement | Detail |
|---|---|
| Azure Subscription | Contributor or Owner access required |
| Azure CLI | `az login` completed with target subscription set |
| Halo ITSM instance | Running and accessible at `https://<your-instance>.haloitsm.com/api` |
| Halo API Key | Available to store in Key Vault during post-deployment |
| Region | **East US 2** (`eastus2`) — required for GPT-4.1 availability |

Set your subscription as default before any steps:

```bash
az account set --subscription "<subscription-id>"
```

---

## 2. Resource Group

**Portal path:** Resource groups → Create

| Setting | Value |
|---|---|
| Name | `rg-aifoundry-<env>-<token>` (e.g., `rg-aifoundry-dev-a67kigj`) |
| Region | East US 2 |
| Tags | See [Common Tags](#19-common-tags) |

---

## 3. User-Assigned Managed Identity

**Portal path:** Managed Identities → Create

This identity is used by all services (APIM, Storage, Key Vault, AI Search, Foundry) so no credentials are embedded in code or configuration.

| Setting | Value |
|---|---|
| Name | `id-ai-foundry-main` |
| Resource Group | *(resource group from step 2)* |
| Region | East US 2 |

After creation, copy the **Client ID** and **Principal (Object) ID** — needed for role assignments and APIM configuration.

---

## 4. Storage Account

**Portal path:** Storage accounts → Create

| Setting | Value |
|---|---|
| Name | `stg<token>` (e.g., `stga67kigj`) — no hyphens, max 24 chars |
| Resource Group | *(resource group from step 2)* |
| Region | East US 2 |
| Performance | Standard |
| Redundancy | LRS (Locally Redundant) |
| Account kind | StorageV2 (General Purpose v2) |
| Hierarchical namespace (HNS) | **Disabled** |
| Allow shared access keys | **Disabled** (RBAC only) |

### Blob Containers

Create the following private containers under **Data Storage → Containers**:

| Container Name | Access Level |
|---|---|
| `load` | Private |


### Role Assignments — Managed Identity on Storage Account (for Blob Trigger Event Loading - Optional)

Navigate to the storage account → **Access Control (IAM)** → Add role assignment for the managed identity (`id-ai-foundry-main`):

| Role | Scope |
|---|---|
| Storage Blob Data Contributor | Storage Account |
| Storage Blob Data Owner | Storage Account |
| Storage Table Data Contributor | Storage Account |
| Storage Account Contributor | Storage Account |
| Storage Queue Data Contributor | Storage Account |

---

## 5. Key Vault

**Portal path:** Key vaults → Create

| Setting | Value |
|---|---|
| Name | `kv-<token>` (e.g., `kv-a67kigj`) — hyphens stripped internally |
| Resource Group | *(resource group from step 2)* |
| Region | East US 2 |
| Pricing tier | Standard |
| Permission model | **Azure role-based access control (RBAC)** |
| Purge protection | Disabled (set to `true` for production) |
| Soft delete retention | 7 days |

### Role Assignments — Managed Identity on Key Vault

Navigate to Key Vault → **Access Control (IAM)** → Add role assignments for the managed identity (`id-ai-foundry-main`):

| Role | Purpose |
|---|---|
| Key Vault Secrets User | Read secrets at runtime (APIM reads Halo API key) |
| Key Vault Crypto User | Cryptographic operations |

### Role Assignments — Deploying User on Key Vault

Add for the user or service principal running the deployment:

| Role | Purpose |
|---|---|
| Key Vault Secrets Officer | Write the Halo API key secret during post-deployment |

---

## 6. Azure Container Registry

**Portal path:** Container registries → Create

| Setting | Value |
|---|---|
| Name | `acr<token>` (e.g., `acra67kigj`) — no hyphens |
| Resource Group | *(resource group from step 2)* |
| Region | East US 2 |
| SKU | Basic |
| Admin user | **Enabled** |

---

## 7. Azure AI Search

**Portal path:** AI Search → Create

| Setting | Value |
|---|---|
| Name | `aisearch-<token>` (e.g., `aisearch-a67kigj`) |
| Resource Group | *(resource group from step 2)* |
| Region | East US 2 |
| Pricing tier | **Basic** (minimum for vector search; `free` tier lacks semantic ranking) |

### Role Assignments — Managed Identity on AI Search

Navigate to AI Search → **Access Control (IAM)**:

| Role | Principal | Purpose |
|---|---|---|
| Search Service Contributor | Managed Identity | Manage index operations |
| Search Index Data Contributor | Managed Identity | Read/write index data |

> The AI Foundry Project's system-assigned identity also needs these two roles (assigned in [step 14](#14-role-assignments-summary) after the project is created).

---

## 8. Application Insights

**Portal path:** Application Insights → Create

| Setting | Value |
|---|---|
| Name | `appi-ai-foundry` |
| Resource Group | *(resource group from step 2)* |
| Region | East US 2 |
| Application type | **Web** |

After creation, copy:
- **Instrumentation Key** — needed for the Foundry project AppInsights connection
- **Resource ID** — needed for the Foundry project AppInsights connection metadata

---

## 9. API Management

**Portal path:** API Management services → Create

### Instance Settings

| Setting | Value |
|---|---|
| Name | `aifoundryapim<token>` (e.g., `aifoundryapim-a67kigj`) |
| Resource Group | *(resource group from step 2)* |
| Region | East US 2 |
| Publisher name | `AI Foundry ITSM` |
| Publisher email | `admin@aifoundry.com` |
| Pricing tier | **Developer** (for dev/test; use **Consumption** for serverless or **Standard/Premium** for production) |
| Capacity units | 1 |

### Managed Identity

Under **Security → Managed identities**:
- Enable **System-assigned**: No
- Enable **User-assigned**: **Yes** — assign `id-ai-foundry-main`

### API — Halo ITSM API

**Portal path:** APIM → APIs → Add API → HTTP

| Setting | Value |
|---|---|
| Display name | `Halo ITSM API` |
| Name | `halo-itsm-api` |
| Description | `Proxies requests to the Halo ITSM instance. Injects the Halo API key from Key Vault via a named value so callers never handle credentials directly.` |
| Web service URL (Backend) | `https://<your-instance>.haloitsm.com/api` |
| API URL suffix | `halo` |
| Protocols | **HTTPS only** |
| Subscription required | **No** |
| API revision | `1` |

#### API Operations

Add the following GET operations under the Halo ITSM API:

**Operation 1 — knowledgebase**

| Setting | Value |
|---|---|
| Display name | `knowledgebase` |
| Name | `knowledgebase` |
| HTTP method | GET |
| URL template | `/KBArticle` |
| Description | `Search and list knowledge base articles from the Halo ITSM knowledge base. Pass the 'search' parameter to filter results by keyword rather than retrieving all articles.` |

Query parameters:

| Name | Required | Type | Description |
|---|---|---|---|
| `search` | No | string | Filter articles by keyword |
| `count` | No | integer | Maximum number of articles to return |
| `pageinate` | No | boolean | Whether to use pagination |
| `page_size` | No | integer | Number of results per page |
| `page_no` | No | integer | Page number to return |

---

**Operation 2 — knowledgebasebyid**

| Setting | Value |
|---|---|
| Display name | `knowledgebasebyid` |
| Name | `knowledgebase-by-id` |
| HTTP method | GET |
| URL template | `/KBArticle/{id}` |
| Description | `Retrieves the full content of a single knowledge base article by its Halo ITSM article ID. Use 'includedetails=true' to ensure the complete article body is returned.` |

Template parameter:

| Name | Required | Type | Description |
|---|---|---|---|
| `id` | Yes | integer | Halo ITSM knowledge base article ID |

Query parameter:

| Name | Required | Type | Description |
|---|---|---|---|
| `includedetails` | No | boolean | Set to `true` to include the full article body |

#### API Tags

Create a tag named `KB` (display name: `KB`) and assign it to both operations above.

#### API Policy (applied after Named Value is configured)

Apply the following policy at the **API level** of the Halo ITSM API (after completing [step 16](#16-post-deployment-configure-apim-named-value)):

```xml
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
```

#### MCP Server

APIM exposes an MCP (Model Context Protocol) endpoint automatically for APIs tagged appropriately. After deployment:

1. Navigate to **APIM → MCP Servers** in the Azure Portal
2. Copy the MCP server URL — this is the value for `MCP_SERVER_URL` in the notebook `.env` file

---

## 10. Microsoft Foundry — AI Services Account

**Portal path:** Azure Portal → Azure AI Services → Create

| Setting | Value |
|---|---|
| Name | `fnd-aifoundry-<env>-<token>` (e.g., `fnd-aifoundry-dev-a67kigj`) |
| Resource Group | *(resource group from step 2)* |
| Region | East US 2 |
| Kind | **AIServices** |
| SKU | **S0** |
| Custom subdomain | Same as the account name |
| Public network access | **Enabled** |
| Allow project management | **Enabled** |
| Disable local auth | **Disabled** (local auth allowed) |
| Network ACLs — default action | **Allow** |

### Managed Identity

Under **Identity**:
- System-assigned: **Off**
- User-assigned: **On** — assign `id-ai-foundry-main`

---

## 11. Microsoft Foundry — Model Deployments

**Portal path:** [ai.azure.com](https://ai.azure.com) → Select your account → Model deployments → Deploy model

#### Deployment 1 — GPT-4.1

| Setting | Value |
|---|---|
| Deployment name | `gpt-4.1` |
| Model | `gpt-4.1` |
| Model version | `2025-04-14` |
| Deployment type | Standard |
| Tokens per minute (TPM) capacity | **150,000** (150K) |
| Version upgrade option | `OnceNewDefaultVersionAvailable` |

#### Deployment 2 — text-embedding-ada-002

| Setting | Value |
|---|---|
| Deployment name | `text-embedding-ada-002` |
| Model | `text-embedding-ada-002` |
| Model version | `2` |
| Deployment type | Standard |
| Tokens per minute (TPM) capacity | **120,000** (120K) |
| Version upgrade option | `OnceNewDefaultVersionAvailable` |

> Create the embedding deployment **after** the GPT-4.1 deployment completes.

---

## 12. Microsoft Foundry — Project

**Portal path:** [ai.azure.com](https://ai.azure.com) → Select your account → Projects → New project

| Setting | Value |
|---|---|
| Name | `proj-aifoundry-<env>-<token>` (e.g., `proj-aifoundry-dev-a67kigj`) |
| Parent account | *(account from step 10)* |
| Identity | **System-assigned** (enabled at project level) |

> Do **not** configure Application Insights in the project properties — this is done as a connection in [step 13](#13-azure-ai-foundry--project-connections).

After the project is created, navigate to **Project → Settings** and copy the **Project Principal ID** (system-assigned managed identity object ID) — needed for Search role assignments in [step 14](#14-role-assignments-summary).

---

## 13. Microsoft Foundry — Project Connections

Both connections can be added via the portal or the Azure CLI.

**Portal path:** [ai.azure.com](https://ai.azure.com) → Select your project → **Admin** (left nav) → **Connected resources** tab → **Add connection**

> Note: **Azure AI Search** can alternatively be added as an agent **Tool** (under Build → Agents → Tools) rather than — or in addition to — a project connection. Adding it as a connection makes it available to all agents in the project; adding it as a tool scopes it to a specific agent.

### Connection 1 — Azure AI Search

Select **Azure AI Search** from the connection type picker, then configure:

| Setting | Value |
|---|---|
| Connection name | `azure-ai-search` |
| Target endpoint | `https://<search-service-name>.search.windows.net` |
| Authentication type | **Microsoft Entra ID (AAD)** — no key required |
| Share to all agents in this project | **Yes** |

> AAD auth requires the Project's system-assigned identity to have Search roles on the AI Search resource — see [step 14](#14-role-assignments-summary).

### Connection 2 — Application Insights

Select **Application Insights** from the connection type picker, then configure:

| Setting | Value |
|---|---|
| Connection name | `azure-app-insights` |
| Target | Application Insights **Resource ID** |
| Authentication type | **ApiKey** |
| Key / Credential | Application Insights **Instrumentation Key** |
| Share to all agents in this project | **Yes** |

### Alternative: Azure CLI

If you prefer scripting over the portal:

```bash
# AI Search connection (AAD auth)
az rest --method PUT \
  --url "https://management.azure.com/subscriptions/<subscription-id>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<account>/projects/<project>/connections/azure-ai-search?api-version=2025-06-01" \
  --body '{"properties":{"category":"CognitiveSearch","target":"https://<search-name>.search.windows.net","authType":"AAD","isSharedToAll":true,"metadata":{"ApiType":"Azure","ResourceId":"<search-resource-id>"}}}'

# Application Insights connection (ApiKey auth)
az rest --method PUT \
  --url "https://management.azure.com/subscriptions/<subscription-id>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<account>/projects/<project>/connections/azure-app-insights?api-version=2025-06-01" \
  --body '{"properties":{"category":"AppInsights","target":"<app-insights-resource-id>","authType":"ApiKey","isSharedToAll":true,"credentials":{"key":"<instrumentation-key>"},"metadata":{"ApiType":"Azure","ResourceId":"<app-insights-resource-id>"}}}'
```

---

## 14. Role Assignments Summary

### Managed Identity (`id-ai-foundry-main`) Role Assignments

| Resource | Role | Purpose |
|---|---|---|
| Storage Account | Storage Blob Data Contributor | Read/write blobs |
| Storage Account | Storage Blob Data Owner | Full blob ownership |
| Storage Account | Storage Table Data Contributor | Table data access |
| Storage Account | Storage Account Contributor | Manage account |
| Storage Account | Storage Queue Data Contributor | Queue access |
| Key Vault | Key Vault Secrets User | Read secrets |
| Key Vault | Key Vault Crypto User | Cryptographic ops |
| AI Search | Search Service Contributor | Manage index ops |
| AI Search | Search Index Data Contributor | Read/write index |
| AI Services Account | Cognitive Services OpenAI User | Invoke models |
| AI Services Account | Cognitive Services User | General data-plane access |

### AI Foundry Project (System-Assigned Identity) Role Assignments

> Assign **after** the project is created (step 12). Target principal: Project's system-assigned object ID.

| Resource | Role | Purpose |
|---|---|---|
| AI Search | Search Index Data Contributor | Agent search tool calls (AAD) |
| AI Search | Search Service Contributor | Agent search management (AAD) |

### Deploying User / Service Principal Role Assignments

| Resource | Role | Purpose |
|---|---|---|
| Key Vault | Key Vault Secrets Officer | Write secrets during deployment |
| AI Services Account | Azure AI Project Manager (`eadc314b-...`) | Create/manage Foundry agents |
| AI Services Account | Azure AI User (`53ca6127-...`) | Invoke agents from notebook |
| AI Services Account | Cognitive Services OpenAI User | Invoke GPT-4.1 / embeddings |

---

## 15. Post-Deployment: Push Halo API Key to Key Vault

After all resources are deployed, store the Halo ITSM API key in Key Vault:

```bash
az keyvault secret set \
  --vault-name "kv-<token>" \
  --name "halo-api-key" \
  --value "<your-halo-api-key>"
```

Copy the resulting **Secret Identifier URI** (e.g., `https://kv-a67kigj.vault.azure.net/secrets/halo-api-key/<version>`) — required for the next step.

---

## 16. Post-Deployment: Configure APIM Named Value

This step links the APIM API policy's `{{halo-api-key}}` placeholder to the Key Vault secret.

**Portal path:** APIM → Named values → Add

| Setting | Value |
|---|---|
| Name | `halo-api-key` |
| Display name | `halo-api-key` |
| Type | **Key Vault** |
| Secret | **Yes** |
| Key Vault secret identifier | URI from [step 15](#15-post-deployment-push-halo-api-key-to-key-vault) |
| Identity | `id-ai-foundry-main` (User-assigned managed identity Client ID) |

After saving the Named Value, apply the API policy from [step 9](#api-policy-applied-after-named-value-is-configured) to the Halo ITSM API.

---

## 17. Post-Deployment: Create Foundry Agent via Notebook

> This section covers creating the agent programmatically using the Azure AI SDK. To create the agent manually via the **Microsoft Foundry portal**, see [deployment_Steps.md — Step 6](deployment_Steps.md#step-6--create-the-foundry-agent) instead.

The notebook `Notebooks/01_azure_ai_agent-mcp.ipynb` creates the **ServiceDeskAssistant** agent programmatically.

### Environment Setup

Create `Notebooks/.env` with the following values:

```env
PROJECT_ENDPOINT=https://<ai-account-name>.cognitiveservices.azure.com/
MODEL_DEPLOYMENT_NAME=gpt-4.1
MCP_SERVER_URL=<apim-gateway-url>/halo/mcp
MCP_SERVER_LABEL=halo-itsm-mcp
```

- `PROJECT_ENDPOINT`: From AI Services account → Overview → Endpoint
- `MCP_SERVER_URL`: From APIM → MCP Servers in Azure Portal

### Agent Configuration

The notebook creates an agent with the following settings:

| Setting | Value |
|---|---|
| Agent name | `ServiceDeskAssistantSDK` |
| Model | `gpt-4.1` |
| Tool | MCPTool — `halo-itsm-mcp` pointing to APIM MCP server URL |
| Approval | `never` (auto-approve all tool calls) |

**System instructions summary:** The agent acts as `ServiceDeskAssistant`, an ITSM support agent. It must:
- Only use Halo ITSM MCP tools to retrieve knowledge base data (no training-data fallback)
- Return full article text verbatim — no summarizing or paraphrasing
- Display article ID in all responses
- Respond with `"Unable to find in knowledge base"` when no result is found

### Install Python Dependencies

```bash
pip install -r Notebooks/requirements.txt
```

### Authentication

The notebook uses `DefaultAzureCredential`. Ensure you are logged in:

```bash
az login
az account set --subscription "<subscription-id>"
```

---

## 18. Naming Conventions

| Resource Type | Pattern | Example |
|---|---|---|
| Resource Group | `rg-aifoundry-<env>-<token>` | `rg-aifoundry-dev-a67kigj` |
| Managed Identity | `id-ai-foundry-main` | `id-ai-foundry-main` |
| AI Services Account | `fnd-aifoundry-<env>-<token>` | `fnd-aifoundry-dev-a67kigj` |
| AI Project | `proj-aifoundry-<env>-<token>` | `proj-aifoundry-dev-a67kigj` |
| Storage Account | `stg<token>` | `stga67kigj` |
| Key Vault | `kv-<token>` | `kv-a67kigj` |
| Container Registry | `acr<token>` | `acra67kigj` |
| AI Search | `aisearch-<token>` | `aisearch-a67kigj` |
| APIM | `aifoundryapim<token>` | `aifoundryapim-a67kigj` |
| App Insights | `appi-ai-foundry` | `appi-ai-foundry` |

> The `<token>` is a short random string (e.g., `a67kigj`) used to ensure globally unique names.

---

## 19. Common Tags

Apply the following tags to all resources:

| Tag | Value |
|---|---|
| `Environment` | `dev` |
| `Project` | `AI-Foundry-ITSM` |
| `ManagedBy` | `Manual` |
| `CreatedBy` | `Manual` |
