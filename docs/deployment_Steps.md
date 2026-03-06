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
| PowerShell | 7+ | **Windows:** `winget install Microsoft.PowerShell` · **Linux/macOS:** [Install guide](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell) |
| Python | 3.10+ | Required for Notebook demo |
| Git | Latest | [Install guide](https://git-scm.com/downloads) |

### Azure Access Requirements

The **deploying user** (the account that runs `deploy.ps1`) requires:

| Requirement | Reason |
|---|---|
| **Owner** or **Contributor** on the target subscription | Terraform creates all resource groups and resources |
| **User Access Administrator** on the subscription | Terraform assigns RBAC roles to the managed identity |

**Workshop participants** (anyone using the Foundry portal or running the notebook) require:

| Role | Scope | How to assign |
|---|---|---|
| `Azure AI User` | AI Foundry account or resource group | Azure Portal → Resource Group → **Access control (IAM)** → Add role assignment → search `Azure AI User` |

> `Azure AI User` grants build and develop (data actions) within the existing Foundry project — sufficient for creating MCP tools, creating agents, using the playground, and running the notebook. The Foundry project is pre-created by Terraform; participants do not need to create it.

### Halo ITSM

You will need your Halo instance URL and an API Key. The API key is obtained by registering a temporary application in Halo.

**Instance URL:**  
Your Halo base URL — e.g., `https://yourinstance.haloitsm.com`

**Registering the application (API Key):**

1. Log in to Halo as an administrator
2. Go to **Configuration → Integrations → Halo API**
3. Click **Authorise a new application**
4. Set **Authentication Method** to `API Key`
5. Under **Permissions**, enable `read:kb` (or `all` if finer scopes are unavailable)
6. Save — Halo will display the generated **API Key**
7. Copy this value — it is used as `-HaloApiKey` in the deploy command and stored in Azure Key Vault at deployment time

> **For workshops:** Register a dedicated application before the workshop and delete it from Halo afterwards (**Configuration → Integrations → Halo API → Remove this Applications**). Participants never see or use this key directly — it is held in Key Vault and injected by APIM as a backend header.

---

## Step 1 — Clone the Repository

```bash
git clone https://github.com/jonathanscholtes/Azure-AI-Foundry-ITSM.git
cd Azure-AI-Foundry-ITSM
```

---

## Step 2 — Deploy Infrastructure

Log in to Azure, then run the deployment orchestrator. This runs Terraform (Phase 1) and stores the Halo API key in Key Vault (Phase 2).

```powershell
az login
az account set --subscription "YOUR-SUBSCRIPTION-ID"
```

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

> **Estimated time:** 15–40 minutes. API Management provisioning is the slowest resource (~30 min).

**Resources created:**
- Resource Group
- Azure AI Services (GPT-4.1 + text-embedding-ada-002 model deployments)
- Azure AI Search
- API Management (with Halo ITSM HTTP API pre-configured)
- Storage Account, Container Registry
- Key Vault (with Halo API key stored as a secret)
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
| `ai_account_endpoint` | Notebook `.env` → `PROJECT_ENDPOINT` |
| `ai_project_name` | Notebook `.env` → `PROJECT_ENDPOINT` (appended to endpoint) |
| `resource_group_name` | Finding resources in the Azure Portal |

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
   | **Tools** | Select both operations: `knowledgebase` (GET /KBArticle) and `knowledgebasebyid` (GET /KBArticle/{id}) |
   | **Description** | `Use this server to interact with Halo ITSM. It provides tools to search and retrieve official knowledge base articles and access service desk data for IT support and incident-response workflows.` |

5. Click **Create**

6. Once created, open the MCP server entry and **copy the MCP Server endpoint URL**  

   The URL format is:
   ```
   https://<apim-name>.azure-api.net/<mcp-server-path>/sse
   ```
   Save this URL — you will need it in Step 5 and Step 7.

---

## Step 5 — Register the MCP Tool in Microsoft Foundry

1. Open the **[Microsoft Foundry portal](https://ai.azure.com/)** and sign in

2. Select your **AI Foundry project**  
   *(Navigate to your subscription → resource group → AI Services account → open in Foundry, or find it directly on the Foundry home page)*

3. In the left menu, go to **Build → Tools**

4. Click **+ Connect a Tool**

5. Choose **Custom → Model Context Protocol (MCP)**

6. Click **Create** and fill in the form:

   | Field | Value |
   |---|---|
   | **Name** | `Halo-ITSM-MCP` |
   | **Remote MCP Server endpoint** | The MCP Server URL copied from Step 4 |
   | **Authentication** | `Subscription key` |
   | **Subscription key** | Your APIM subscription key *(see below)* |

   > **To get the APIM subscription key:**  
   > Azure Portal → your APIM instance → **Subscriptions** → find the `Built-in all-access` or `Halo ITSM` subscription → click the `...` menu → **Show/hide keys** → copy the primary key.

7. Click **Connect**

---

## Step 6 — Create the Foundry Agent

1. In the Foundry portal, go to **Build → Agents**

2. Click **+ New agent** → **From scratch**

3. Configure the agent:

   | Field | Value |
   |---|---|
   | **Name** | `ServiceDeskAssistant` |
   | **Model** | `gpt-4.1` |
   | **Description** | `An AI-powered service desk assistant that retrieves IT support answers from the Halo ITSM knowledge base.` |

4. In the **Instructions** (System Prompt) field, paste the following:

   ```
   You are ServiceDeskAssistant, an intelligent IT service desk support agent. Your primary role is to help users with IT support requests, incident management, and knowledge base queries.

   IMPORTANT GUIDELINES:
   - You MUST ONLY use the provided Halo-ITSM-MCP tools to search and retrieve information from the knowledge base
   - Do NOT rely on your training data or general knowledge to answer questions
   - For every user query, search the knowledge base using the available tools
   - If the information is not found in the knowledge base after searching, you MUST respond with: "Unable to find in knowledge base"
   - Always show the article id
   - Always output the FULL article text exactly as returned by the tool — do not summarize or paraphrase

   KNOWLEDGE BASE ARTICLE HANDLING (STRICT VERBATIM RULE):
   When a knowledge base article is found:
   1) Retrieve the FULL article body using the appropriate tool (not just a search preview)
   2) Output the ENTIRE article text exactly as returned by the tool
   3) Do NOT summarize, paraphrase, shorten, or rewrite any part of the article
   4) Do NOT remove any sections or metadata (title, dates, article ID, description, resolution, steps)
   ```

5. Under **Tools**, click **+ Add tool** and select `Halo-ITSM-MCP`

6. Click **Create** to save the agent

7. Test the agent in the **Playground** with a sample query:
   - *"How do I reset my password?"*
   - *"My laptop charger is damaged, how do I get a replacement?"*
   - *"How do I set up VPN to work from home?"*

   > See [prompt_examples.md](prompt_examples.md) for a full set of categorised test prompts, including out-of-scope queries that demonstrate grounding behaviour.

---

## Step 7 — Set Up the Notebook (Optional — SDK Demo)

The notebook (`Notebooks/01_azure_ai_agent-mcp.ipynb`) demonstrates creating and running the agent programmatically via the Azure AI Projects SDK.

### 7a — Create the `.env` file

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
```

### 7b — Install Python dependencies

```bash
cd Notebooks
pip install -r requirements.txt
```

### 7c — Authenticate and run

Ensure you are logged in with an account that has the `Azure AI User` role on the Foundry project:

```bash
az login
```

Open `01_azure_ai_agent-mcp.ipynb` in VS Code or Jupyter and run cells in order.

---

## Step 8 — Clean Up

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
| APIM returns 401 on MCP calls | Wrong or missing subscription key | Check the subscription key in APIM → Subscriptions |
| `halo_base_url` not resolving | Wrong URL format | Ensure URL ends with `/api` (no trailing slash), e.g. `https://your.haloitsm.com/api` |
| Can't find Foundry project | Wrong subscription or region | Run `az account show` to confirm the active subscription |
| MCP server not visible in APIM | APIM not fully provisioned | Wait 5 min and refresh the portal; APIM UI can lag after initial provision |
