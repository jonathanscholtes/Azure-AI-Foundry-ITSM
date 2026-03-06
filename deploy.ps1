# Microsoft Foundry ITSM - Main Deployment Orchestrator
# This script coordinates the full end-to-end deployment
#
# Usage:
#   Deploy:  .\deploy.ps1 -Subscription '...' -HaloBaseUrl '...' [-HaloApiKey '...']
#   Destroy: .\deploy.ps1 -Subscription '...' -Destroy

param (
    [Parameter(Mandatory=$true)]
    [string]$Subscription,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus2",
    
    [Parameter(Mandatory=$false)]
    [string]$Environment = "dev",
    
    [Parameter(Mandatory=$false)]
    [string]$HaloApiKey,

    [Parameter(Mandatory=$false)]
    [string]$HaloBaseUrl,

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

& "$PSScriptRoot/scripts/Deploy-Infrastructure.ps1" `
    -Action $Action `
    -Subscription $Subscription `
    -Location $Location `
    -Environment $Environment `
    -HaloBaseUrl $HaloBaseUrl

if (-not $? -or $LASTEXITCODE -ne 0) {
    Write-Host "Infrastructure deployment failed" -ForegroundColor Red
    exit 1
}

if (-not $HaloApiKey) {
    Write-Host "`n[Warning] -HaloApiKey not provided - skipping APIM Key Vault configuration." -ForegroundColor Yellow
    Write-Host "           Re-run with -HaloApiKey if you need to store or update the Halo API key.`n" -ForegroundColor Yellow
} else {
    # PHASE 2: Deploy APIM Configuration
    Write-Host "`n=== PHASE 2: APIM Configuration ==="  -ForegroundColor Magenta

    & "$PSScriptRoot/scripts/Deploy-APIM-Configuration.ps1" `
        -Subscription $Subscription `
        -HaloApiKey $HaloApiKey `
        -Environment $Environment

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
if ($HaloApiKey) {
    Write-Success "Halo API Key stored in Key Vault"
} else {
    Write-Host "  [Skipped] Halo API Key not provided - APIM Key Vault configuration skipped" -ForegroundColor Yellow
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
