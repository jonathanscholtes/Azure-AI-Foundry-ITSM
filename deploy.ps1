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
    [switch]$Destroy
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

Write-Host "`n=== Next Steps ===" -ForegroundColor Cyan
Write-Host "1. Run 'cd infra && terraform output' to view resource endpoints" -ForegroundColor Gray
Write-Host "2. Create the MCP server in APIM (see docs/deployment_Steps.md - Step 4)" -ForegroundColor Gray
Write-Host "3. Register the MCP tool and create the agent in Microsoft Foundry (see docs/deployment_Steps.md - Steps 5 & 6)" -ForegroundColor Gray
Write-Host "4. Copy Notebooks/.env.sample to Notebooks/.env and fill in values from terraform output" -ForegroundColor Gray

Write-Host @"

============================================================
           Deployment Complete!
============================================================

"@ -ForegroundColor Green
