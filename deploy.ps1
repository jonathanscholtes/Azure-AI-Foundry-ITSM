# Microsoft Foundry ITSM - Main Deployment Orchestrator
# This script coordinates the full end-to-end deployment
#
# Usage:
#   Deploy (API Key):  .\deploy.ps1 -Subscription '...' -HaloBaseUrl '...' [-HaloApiKey '...']
#   Deploy (OAuth):    .\deploy.ps1 -Subscription '...' -HaloBaseUrl '...' -HaloAuthMethod 'oauth' -HaloClientId '...' -HaloClientSecret '...' -HaloAuthUrl '...'
#   Destroy:           .\deploy.ps1 -Subscription '...' -Destroy

param (
    [Parameter(Mandatory=$true)]
    [string]$Subscription,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus2",
    
    [Parameter(Mandatory=$false)]
    [string]$Environment = "dev",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("apikey", "oauth")]
    [string]$HaloAuthMethod = "apikey",

    [Parameter(Mandatory=$false)]
    [string]$HaloApiKey,

    [Parameter(Mandatory=$false)]
    [string]$HaloBaseUrl,

    [Parameter(Mandatory=$false)]
    [string]$HaloClientId,

    [Parameter(Mandatory=$false)]
    [string]$HaloClientSecret,

    [Parameter(Mandatory=$false)]
    [string]$HaloAuthUrl,

    [Parameter(Mandatory=$false)]
    [string]$HaloTenant,

    [Parameter(Mandatory=$false)]
    [switch]$Destroy,

    # Run New-GitHubOidc.ps1 to create/update the Entra app registration and
    # set the 3 GitHub Actions secrets automatically. Requires 'gh' CLI.
    [Parameter(Mandatory=$false)]
    [switch]$SetupGitHub
)

# Determine the action: deploy (all) or destroy
$Action = if ($Destroy) { "destroy" } else { "all" }

# Deploying requires HaloBaseUrl for tfvars generation
if (-not $Destroy -and -not $HaloBaseUrl) {
    Write-Error "'-HaloBaseUrl' is required for deployment. Example: -HaloBaseUrl 'https://yourinstance.haloitsm.com/api'"
    exit 1
}

# OAuth mode requires additional parameters
if (-not $Destroy -and $HaloAuthMethod -eq "oauth") {
    if (-not $HaloAuthUrl) {
        Write-Error "'-HaloAuthUrl' is required for OAuth authentication. Example: -HaloAuthUrl 'https://yourinstance.haloitsm.com/auth/token'"
        exit 1
    }
}

Set-StrictMode -Version Latest
Set-Variable -Name ErrorActionPreference -Value 'Stop'


# Import common functions
Import-Module "$PSScriptRoot/scripts/common/DeploymentFunctions.psm1" -Force

Write-Host @"

============================================================
  Agentic Service Help Desk - Deployment Orchestrator
============================================================

"@ -ForegroundColor Cyan

# Initialize Azure context
Initialize-AzureContext -Subscription $Subscription

if ($Destroy) {
    # ===== DESTROY MODE =====
    Write-Host "`n=== Destroying Infrastructure ===" -ForegroundColor Red

    & "$PSScriptRoot/scripts/Deploy-Infrastructure.ps1" `
        -Action "destroy" `
        -Subscription $Subscription `
        -Location $Location `
        -Environment $Environment

    if (-not $? -or $LASTEXITCODE -ne 0) {
        Write-Host "Infrastructure destruction failed" -ForegroundColor Red
        exit 1
    }

    Write-Host "`n=== All resources destroyed ===" -ForegroundColor Green
    exit 0
}

# ===== DEPLOY MODE =====

# PHASE 1: Deploy Infrastructure
Write-Host "`n=== PHASE 1: Infrastructure Deployment ===" -ForegroundColor Magenta

$infraParams = @{
    Action       = $Action
    Subscription = $Subscription
    Location     = $Location
    Environment  = $Environment
    HaloBaseUrl  = $HaloBaseUrl
}
if ($HaloAuthMethod -eq "oauth" -and $HaloAuthUrl) {
    $infraParams.HaloAuthUrl = $HaloAuthUrl
}

& "$PSScriptRoot/scripts/Deploy-Infrastructure.ps1" @infraParams

if (-not $? -or $LASTEXITCODE -ne 0) {
    Write-Host "Infrastructure deployment failed" -ForegroundColor Red
    exit 1
}

$hasCredentials = if ($HaloAuthMethod -eq "oauth") { $HaloClientId -and $HaloClientSecret } else { [bool]$HaloApiKey }

if (-not $hasCredentials) {
    if ($HaloAuthMethod -eq "oauth") {
        Write-Host "`n[Warning] -HaloClientId and/or -HaloClientSecret not provided - skipping APIM Key Vault configuration." -ForegroundColor Yellow
        Write-Host "           Re-run with -HaloClientId and -HaloClientSecret to configure OAuth.`n" -ForegroundColor Yellow
    } else {
        Write-Host "`n[Warning] -HaloApiKey not provided - skipping APIM Key Vault configuration." -ForegroundColor Yellow
        Write-Host "           Re-run with -HaloApiKey if you need to store or update the Halo API key.`n" -ForegroundColor Yellow
    }
} else {
    # PHASE 2: Deploy APIM Configuration
    Write-Host "`n=== PHASE 2: APIM Configuration ==="  -ForegroundColor Magenta

    $apimParams = @{
        Subscription   = $Subscription
        Environment    = $Environment
        HaloAuthMethod = $HaloAuthMethod
    }
    if ($HaloAuthMethod -eq "oauth") {
        $apimParams.HaloClientId     = $HaloClientId
        $apimParams.HaloClientSecret = $HaloClientSecret
        $apimParams.HaloAuthUrl      = $HaloAuthUrl
        if ($HaloTenant) { $apimParams.HaloTenant = $HaloTenant }
    } else {
        $apimParams.HaloApiKey = $HaloApiKey
    }

    & "$PSScriptRoot/scripts/Deploy-APIM-Configuration.ps1" @apimParams

    if (-not $? -or $LASTEXITCODE -ne 0) {
        Write-Host "APIM configuration failed" -ForegroundColor Red
        exit 1
    }
}

# Read Terraform outputs for downstream phases
Write-Host "`n=== Reading Terraform Outputs ===" -ForegroundColor Cyan
Push-Location "$PSScriptRoot/infra"
$tfOutputJson = terraform output -json 2>$null
Pop-Location

$tfOutputs = @{}
if ($tfOutputJson) {
    $parsed = $tfOutputJson | ConvertFrom-Json
    foreach ($prop in $parsed.PSObject.Properties) {
        $tfOutputs[$prop.Name] = $prop.Value.value
    }
}

$acrServer = $tfOutputs["container_registry_login_server"]
$aiProjectEndpoint = $tfOutputs["ai_project_endpoint"]
$rgName = $tfOutputs["resource_group_name"]

# PHASE 1.5: Build and Push Containers (if ACR exists)
if ($acrServer) {
    Write-Host "`n=== PHASE 1.5: Container Build ===" -ForegroundColor Magenta
    $acrName = $acrServer -replace '\.azurecr\.io$', ''

    & "$PSScriptRoot/scripts/Deploy-Containers.ps1" `
        -ContainerRegistryName $acrName `
        -ResourceGroupName $rgName `
        -Images @("itsm-api", "itsm-ui") `
        -Tag "latest"

    if (-not $? -or $LASTEXITCODE -ne 0) {
        Write-Host "Container build failed" -ForegroundColor Red
        exit 1
    }

    # Update both container apps to the real ACR images now that they exist
    Write-Host "`nUpdating container apps to real ACR images..." -ForegroundColor Cyan

    $caUpdates = @(
        @{ Name = $tfOutputs["container_app_name"];    Image = "$acrServer/itsm-api:latest" },
        @{ Name = $tfOutputs["container_app_ui_name"]; Image = "$acrServer/itsm-ui:latest" }
    )
    foreach ($ca in $caUpdates) {
        if (-not $ca.Name) { continue }
        Write-Host "  Updating $($ca.Name) -> $($ca.Image)" -ForegroundColor Gray
        az containerapp update `
            --name $ca.Name `
            --resource-group $rgName `
            --image $ca.Image `
            --output none
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: Failed to update $($ca.Name) - the placeholder will remain until next deploy." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "`n[Info] Container Registry not found in Terraform outputs - skipping container build" -ForegroundColor Yellow
}

# PHASE 3: Deploy Foundry Agents
if ($aiProjectEndpoint) {
    Write-Host "`n=== PHASE 3: Foundry Agent Deployment ===" -ForegroundColor Magenta

    $agentParams = @{
        AiProjectEndpoint = $aiProjectEndpoint
        ModelDeployment   = "gpt-4.1"
    }

    # Pass App Configuration endpoint so agent IDs are persisted for container app consumption
    $appConfigEndpoint = $tfOutputs["app_configuration_endpoint"]
    if ($appConfigEndpoint) {
        $agentParams.AppConfigEndpoint = $appConfigEndpoint
    }

    # Pass MCP config if APIM is configured
    $apimGatewayUrl = $tfOutputs["apim_gateway_url"]
    if ($apimGatewayUrl) {
        $agentParams.McpServerUrl = "$apimGatewayUrl/halo-itsm-mcp/mcp"
        $agentParams.McpServerLabel = "halo-itsm-mcp"
    }

    # Fetch APIM subscription key via Azure REST API (listSecrets).
    # Terraform cannot export APIM subscription keys, so we call the ARM API directly.
    $apimName = $tfOutputs["apim_name"]
    if ($apimName) {
        Write-Host "  Retrieving APIM subscription key..." -ForegroundColor Gray
        $subId = (az account show --query id -o tsv)
        $secretsUri = "/subscriptions/$subId/resourceGroups/$rgName" +
                      "/providers/Microsoft.ApiManagement/service/$apimName" +
                      "/subscriptions/ai-agent-subscription/listSecrets?api-version=2022-08-01"
        $apimSubKey = (az rest --method post --uri $secretsUri 2>$null | ConvertFrom-Json).primaryKey
        if ($apimSubKey) {
            $agentParams.ApimSubscriptionKey = $apimSubKey
        } else {
            Write-Host "  [Warning] Could not retrieve APIM subscription key - agents will be deployed without MCP tools." -ForegroundColor Yellow
        }
    }

    & "$PSScriptRoot/scripts/Deploy-FoundryAgents.ps1" @agentParams

    if (-not $? -or $LASTEXITCODE -ne 0) {
        Write-Host "Agent deployment failed" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "`n[Info] AI Project endpoint not found in Terraform outputs - skipping agent deployment" -ForegroundColor Yellow
}

# Deployment Summary
Write-Host @"

============================================================
                 Deployment Summary
============================================================

"@ -ForegroundColor Cyan
Write-Success "All Azure resources provisioned (AI Services, AI Search, APIM, Storage, Key Vault)"
Write-Success "Terraform configuration applied successfully"
if ($hasCredentials) {
    if ($HaloAuthMethod -eq "oauth") {
        Write-Success "Halo OAuth credentials (client_id, client_secret) stored in Key Vault"
    } else {
        Write-Success "Halo API Key stored in Key Vault"
    }
} else {
    Write-Host "  [Skipped] Halo credentials not provided - APIM Key Vault configuration skipped" -ForegroundColor Yellow
}
if ($acrServer) {
    Write-Success "Container images built and pushed to ACR"
}
if ($aiProjectEndpoint) {
    Write-Success "Foundry agents deployed/versioned"
}

# PHASE 4: GitHub OIDC setup (optional)
if ($SetupGitHub) {
    Write-Host "`n=== PHASE 4: GitHub OIDC Setup ===" -ForegroundColor Magenta

    & "$PSScriptRoot/scripts/New-GitHubOidc.ps1"

    if (-not $? -or $LASTEXITCODE -ne 0) {
        Write-Host "GitHub OIDC setup failed" -ForegroundColor Red
        exit 1
    }
}

Write-Host "`n=== Next Steps ===" -ForegroundColor Cyan
Write-Host "1. Run 'cd infra && terraform output' to view resource endpoints" -ForegroundColor Gray
Write-Host "2. Create the MCP server in APIM (see docs/deployment_Steps.md - Step 4)" -ForegroundColor Gray
Write-Host "3. Copy Notebooks/.env.sample to Notebooks/.env and fill in values from terraform output" -ForegroundColor Gray

Write-Host @"

============================================================
           Deployment Complete!
============================================================

"@ -ForegroundColor Green
