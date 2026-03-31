# Deployment Steps

Complete step-by-step guide for deploying and configuring the Microsoft Foundry ITSM solution.

---

## Prerequisites

### Tools

Ensure the following are installed before starting:

| Tool | Version | Install |
|---|---|---|
| Terraform | >= 1.5 | **Windows:** `winget install HashiCorp.Terraform` · **macOS:** `brew install hashicorp/tap/terraform` · **Linux:** [Install guide](https://developer.hashicorp.com/terraform/install) |
| Azure CLI | Latest | [Install guide](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) |
| PowerShell | 5.1+ (Windows) · 7+ (Linux/macOS) | **Windows:** Built-in (5.1) or `winget install Microsoft.PowerShell` for 7+ · **Linux/macOS:** [Install guide](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell) |
| Python | 3.10+ | Required for Notebook demo |
| Git | Latest | [Install guide](https://git-scm.com/downloads) |

### Azure Access Requirements

The **deploying user** (the account that runs `deploy.ps1`) requires:

| Requirement | Reason |
|---|---|
| **Owner** or **Contributor** on the target subscription | Terraform creates all resource groups and resources |
| **User Access Administrator** on the subscription | Terraform assigns RBAC roles to the managed identity |

**Users** (anyone using the Foundry portal or running the notebook) require:

| Role | Scope | How to assign |
|---|---|---|
| `Azure AI User` | AI Foundry account or resource group | Azure Portal → Resource Group → **Access control (IAM)** → Add role assignment → search `Azure AI User` |

> `Azure AI User` grants build and develop (data actions) within the existing Foundry project — sufficient for creating MCP tools, creating agents, using the playground, and running the notebook. The Foundry project is pre-created by Terraform; participants do not need to create it.

### Halo ITSM

You will need your Halo instance URL and credentials. The deployment supports two authentication methods:

**Instance URL:**  
Your Halo base URL — e.g., `https://yourinstance.haloitsm.com`

#### Option A — API Key (default)

1. Log in to Halo as an administrator
2. Go to **Configuration → Integrations → Halo API**
3. Click **Authorise a new application**
4. Set **Authentication Method** to `API Key`
5. Under **Permissions**, enable `read:kb` (or `all` if finer scopes are unavailable)
6. Save — Halo will display the generated **API Key**
7. Copy this value — it is used as `-HaloApiKey` in the deploy command and stored in Azure Key Vault at deployment time

> Register a dedicated application and delete it from Halo when no longer needed (**Configuration → Integrations → Halo API → Remove this Applications**). Users never see or use this key directly — it is held in Key Vault and injected by APIM as a backend header.

#### Option B — OAuth Client Credentials (bearer token)

Use this method if your Halo instance requires OAuth 2.0 Client Credentials authentication.

1. Log in to Halo as an administrator
2. Go to **Configuration → Integrations → Halo API**
3. Click **Authorise a new application**
4. Set **Authentication Method** to `Client ID and Secret (OAuth 2.0)`
5. Under **Permissions**, enable `read:kb` (or `all` if finer scopes are unavailable)
6. Save — Halo will display the **Client ID** and **Client Secret**
7. Copy both values — they are used as `-HaloClientId` and `-HaloClientSecret` in the deploy command
8. Note your **Auth URL** — typically `https://yourinstance.haloitsm.com/auth/token`

> The Client ID and Client Secret are stored in Azure Key Vault. APIM acquires a bearer token at runtime using the OAuth 2.0 Client Credentials grant and caches it (just under 1 hour). Callers never handle credentials directly.

---

## Step 1 — Clone the Repository

```bash
git clone https://github.com/jonathanscholtes/Azure-AI-Foundry-ITSM.git
cd Azure-AI-Foundry-ITSM
```

---

## Step 2 — Deploy Infrastructure

Log in to Azure, then run the deployment orchestrator. This runs Terraform (Phase 1) and stores the Halo credentials in Key Vault (Phase 2).

```powershell
az login
az account set --subscription "YOUR-SUBSCRIPTION-ID"
```

### Option A — API Key authentication (default)

**Windows:**
```powershell
.\deploy.ps1 `
    -Subscription "YOUR-SUBSCRIPTION-ID" `
    -Location "eastus2" `
    -Environment "dev" `
    -HaloApiKey "YOUR-HALO-API-KEY" `
    -HaloBaseUrl "https://YOURINSTANCE.haloitsm.com/api"
```

**Linux / macOS:**
```powershell
pwsh ./deploy.ps1 `
    -Subscription "YOUR-SUBSCRIPTION-ID" `
    -Location "eastus2" `
    -Environment "dev" `
    -HaloApiKey "YOUR-HALO-API-KEY" `
    -HaloBaseUrl "https://YOURINSTANCE.haloitsm.com/api"
```

### Option B — OAuth Client Credentials (bearer token)

**Windows:**
```powershell
.\deploy.ps1 `
    -Subscription "YOUR-SUBSCRIPTION-ID" `
    -Location "eastus2" `
    -Environment "dev" `
    -HaloAuthMethod "oauth" `
    -HaloClientId "YOUR-CLIENT-ID" `
    -HaloClientSecret "YOUR-CLIENT-SECRET" `
    -HaloAuthUrl "https://YOURINSTANCE.haloitsm.com/auth/token" `
    -HaloBaseUrl "https://YOURINSTANCE.haloitsm.com/api"
```

**Linux / macOS:**
```powershell
pwsh ./deploy.ps1 `
    -Subscription "YOUR-SUBSCRIPTION-ID" `
    -Location "eastus2" `
    -Environment "dev" `
    -HaloAuthMethod "oauth" `
    -HaloClientId "YOUR-CLIENT-ID" `
    -HaloClientSecret "YOUR-CLIENT-SECRET" `
    -HaloAuthUrl "https://YOURINSTANCE.haloitsm.com/auth/token" `
    -HaloBaseUrl "https://YOURINSTANCE.haloitsm.com/api"
```

> **Estimated time:** 15–40 minutes. API Management provisioning is the slowest resource (~30 min).

**Resources created:**
- Resource Group
- Azure AI Services (GPT-4.1 + text-embedding-ada-002 model deployments)
- Azure AI Search
- API Management (with Halo ITSM HTTP API pre-configured)
- Storage Account, Container Registry
- Key Vault (with Halo API key or OAuth client credentials stored as secrets)
- User-Assigned Managed Identity + RBAC assignments
- Application Insights + Log Analytics Workspace

---

## Step 3 — Retrieve Deployment Outputs

After deployment completes, collect the values you will need in later steps:

```powershell
cd infra
terraform output
```

Note these values:

| Output | Where you'll use it |
|---|---|
| `apim_gateway_url` | Base URL for the APIM MCP server endpoint |
| `apim_name` | Finding the APIM instance in the Azure Portal |
| `apim_subscription_key` | APIM subscription key for authenticating API/MCP calls (sensitive — use `terraform output -raw apim_subscription_key`). Alternatively, retrieve it from the Azure Portal (see below). |
| `ai_account_endpoint` | Notebook `.env` → `PROJECT_ENDPOINT` |
| `ai_project_name` | Notebook `.env` → `PROJECT_ENDPOINT` (appended to endpoint) |
| `resource_group_name` | Finding resources in the Azure Portal |

**Retrieving the subscription key from the Azure Portal:**

1. Navigate to your **API Management** instance in the Azure Portal
2. In the left menu, click **Subscriptions**
3. Find the **AI Agent Subscription** row
4. Click the **⋯** (ellipsis) menu → **Show/hide keys**
5. Copy the **Primary key**

---

## Step 4 — Create the MCP Server in APIM

The Halo ITSM HTTP API is already deployed in APIM by Terraform. This step wraps it as an MCP server that Foundry can call.

1. Open the **[Azure Portal](https://portal.azure.com)** and navigate to your **API Management** instance  
   *(Search for the `apim_name` value from Step 3, or browse to your resource group)*

2. In the left menu, select **APIs → MCP Servers**

3. Click **+ Create** → **Expose an API as an MCP server**

4. Fill in the form:

   | Field | Value |
   |---|---|
   | **Name** | `Halo-ITSM-MCP` |
   | **API** | `Halo ITSM API` *(the API deployed by Terraform)* |
   | **Tools** | Select all four operations: `knowledgebase` (GET /KBArticle), `knowledgebasebyid` (GET /KBArticle/{id}), `tickets` (GET /Tickets), and `ticketsbyid` (GET /Tickets/{id}) |
   | **Description** | `Use this server to interact with Halo ITSM. It provides tools to search and retrieve official knowledge base articles, list and look up support tickets, and access service desk data for IT support and incident-response workflows.` |

5. Under **Subscription**, check **Subscription required** and verify the key names:

   | Setting | Value |
   |---|---|
   | **Subscription required** | **Checked** |
   | **Header name** | `Ocp-Apim-Subscription-Key` |
   | **Query parameter name** | `subscription-key` |

6. Click **Create**

7. Once created, open the MCP server entry and **copy the MCP Server endpoint URL**  

   The URL format is:
   ```
   https://<apim-name>.azure-api.net/<mcp-server-path>/mcp
   ```
   Save this URL — you will need it in Step 5 and Step 7.

   > **Important:** The MCP Server is a separate API from the Halo ITSM API. The APIM subscription must be scoped to **All APIs** (not a single API) so the key works for both the Halo API and the MCP Server endpoint.

---

## Step 5 — Create the Foundry Agent

1. Open the **[Microsoft Foundry portal](https://ai.azure.com/)** and sign in

2. Select your **Foundry project**  
   *(Navigate to your subscription → resource group → AI Services account → open in Foundry, or find it directly on the Foundry home page)*

3. In the left menu, go to **Build → Agents**

4. Click **+ New agent** → **From scratch**

5. Configure the agent:

   | Field | Value |
   |---|---|
   | **Name** | `ServiceDeskAssistant` |
   | **Model** | `gpt-4.1` |
   | **Description** | `An AI-powered service desk assistant that retrieves IT support answers from the Halo ITSM knowledge base.` |

6. In the **Instructions** (System Prompt) field, paste the following:

   ```
   You are ServiceDeskAssistant, an intelligent IT service desk support agent. Your primary role is to help users with IT support requests, incident management, and knowledge base queries.

   IMPORTANT GUIDELINES:
   - You MUST ONLY use the provided Halo-ITSM-MCP tools to search and retrieve information from the knowledge base
   - Do NOT rely on your training data or general knowledge to answer questions
   - For every user query, search the knowledge base using the available tools
   - If the information is not found in the knowledge base after searching, you MUST respond with: "I am not able to find information in Halo that matches your question"
   - Do NOT attempt to provide answers based on general knowledge if they are not found in the knowledge base
   - Always be honest about the limitations of available information in the system
   - Always show the **article id**

   SEARCH QUALITY:
   - Before calling the knowledge base search tool, extract the core technical subject from the user's message to use as the search query
   - Drop leading phrases like "how do I", "can you help me with", "tell me about", or "what is the process for" — keep the remaining topic keywords
   - Always search when the message contains an identifiable IT topic, even if it also contains filler words
   - Examples:
   - User: "how do I reset my password" → search: "reset password"
   - User: "How do I configure my printer to print double-sided by default?" → search: "configure printer double-sided"
   - User: "what is the process for requesting new hardware" → search: "requesting new hardware"
   - User: "VPN" → search: "VPN" (already specific, use as-is)
   - Only ask the user to clarify if their message has no identifiable IT topic at all (e.g., "how" by itself, "hello", "help me")

   KNOWLEDGE BASE ARTICLE HANDLING (STRICT VERBATIM RULE):
   When a knowledge base article is found:
   1) You MUST retrieve the FULL article body using the appropriate tool (not just a search preview).
   2) You MUST output the ENTIRE article text exactly as returned by the tool.
   3) You MUST NOT summarize, paraphrase, shorten, or rewrite any part of the article.
   4) You MUST NOT remove any sections or metadata (title, created/edited dates, review dates, article ID, description, resolution, steps).
   5) When the article contains HTML content (such as <img> tags), you MUST preserve the original HTML tags exactly as they appear. Do NOT convert HTML <img> tags to markdown image syntax (![alt](url)).
   ```

7. Under **Tools**, click **Add**

8. Choose **Custom** --> **Model Context Protocol (MCP)**

9. Fill in the connection form:

   | Field | Value |
   |---|---|
   | **Name** | `Halo-ITSM-MCP` |
   | **Remote MCP Server endpoint** | The MCP Server URL copied from Step 4 |
   | **Authentication** | `Key-based` |
   | **Credential** | Key: `Ocp-Apim-Subscription-Key`  Value: *(the subscription key from Step 3 — `terraform output -raw apim_subscription_key`)* |

   > The APIM API requires a subscription key. The Halo API key is injected separately as a backend header by the APIM policy — callers never handle Halo credentials directly.

10. Click **Add** to add the tool

11. On the tool card for `Halo-ITSM-MCP`, click the **⋯** (three dots) menu and select **Configure**

12. Set **Approval setting for tools in this MCP server for this agent** to **Always auto-approve all tools**, then click **Add**

13. Click **Create** to save the agent

14. Test the agent in the **Playground** with a sample query:
    - *"How do I reset my password?"*
    - *"My laptop charger is damaged, how do I get a replacement?"*
    - *"How do I set up VPN to work from home?"*

    > See [prompt_examples.md](prompt_examples.md) for a full set of categorised test prompts, including out-of-scope queries that demonstrate grounding behaviour.

---

## Step 6 — Set Up the Notebook (Optional — SDK Demo)

The notebook (`Notebooks/01_azure_ai_agent-mcp.ipynb`) demonstrates creating and running the agent programmatically via the Azure AI Projects SDK.

### 6a — Create the `.env` file

```bash
cp Notebooks/.env.sample Notebooks/.env
```

Edit `Notebooks/.env` with the values from Step 3 and Step 4:


```env
# AI Foundry project endpoint
# Format: {ai_account_endpoint}/api/projects/{ai_project_name}
# Values from: terraform output ai_account_endpoint  and  terraform output ai_project_name
PROJECT_ENDPOINT=https://<your-ai-account>.services.ai.azure.com/api/projects/<project-name>

# Model deployment name
MODEL_DEPLOYMENT_NAME=gpt-4.1

# MCP server URL — the MCP endpoint from Step 4
MCP_SERVER_URL=https://<apim-name>.azure-api.net/<mcp-path>/mcp

# A local label for the MCP server connection
MCP_SERVER_LABEL=halo-itsm-mcp

# APIM subscription key — required to authenticate with the APIM gateway
# Value from: terraform output -raw apim_subscription_key
APIM_SUBSCRIPTION_KEY=<your-apim-subscription-key>
```

### 6b — Install Python dependencies

```bash
cd Notebooks
pip install -r requirements.txt
```

### 6c — Authenticate and run

Ensure you are logged in with an account that has the `Azure AI User` role on the Foundry project:

```bash
az login
```

Open `01_azure_ai_agent-mcp.ipynb` in VS Code or Jupyter and run cells in order.

---

## Step 7 — Clean Up

When finished, destroy all Azure resources to avoid ongoing charges:

**Windows:**
```powershell
.\deploy.ps1 -Subscription "YOUR-SUBSCRIPTION-ID" -Destroy
```

**Linux / macOS:**
```powershell
pwsh ./deploy.ps1 -Subscription "YOUR-SUBSCRIPTION-ID" -Destroy
```

Or manually:
```powershell
cd infra
terraform destroy
```

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| `FlagMustBeSetForRestore` on AI Services | Soft-deleted account from a previous destroy | Run: `az cognitiveservices account purge --name <name> --resource-group <rg> --location <region>` then re-deploy |
| `terraform apply` fails on APIM | APIM provisioning timeout (common) | Re-run `.\deploy.ps1` with the same parameters — Terraform is idempotent |
| Notebook `AuthenticationError` | Missing role assignment | Ensure your account has `Azure AI User` on the AI Foundry resource |
| Agent returns no results | MCP tool not connected to agent | In Foundry portal → agent → verify `Halo-ITSM-MCP` is listed under Tools |
| APIM returns 401 on MCP calls | Halo credentials not injected by APIM | **API Key mode:** Re-run `deploy.ps1` with `-HaloApiKey` to push the Key Vault secret. **OAuth mode:** Re-run with `-HaloAuthMethod "oauth" -HaloClientId "..." -HaloClientSecret "..." -HaloAuthUrl "..."` to push OAuth secrets and apply the policy via Terraform |
| `halo_base_url` not resolving | Wrong URL format | Ensure URL ends with `/api` (no trailing slash), e.g. `https://your.haloitsm.com/api` |
| Can't find Foundry project | Wrong subscription or region | Run `az account show` to confirm the active subscription |
| MCP server not visible in APIM | APIM not fully provisioned | Wait 5 min and refresh the portal; APIM UI can lag after initial provision |
