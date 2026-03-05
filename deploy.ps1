# Agentic Service Help Desk  - Main Deployment Orchestrator
# This script coordinates the full end-to-end deployment

param (
    [Parameter(Mandatory=$false)]
    [ValidateSet("init", "validate", "plan", "apply", "all", "destroy", "output", "fmt", "clean")]
    [string]$Action = "all",
    
    [Parameter(Mandatory=$true)]
    [string]$Subscription,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus2",
    
    [Parameter(Mandatory=$false)]
    [string]$Environment = "dev",
    
    [Parameter(Mandatory=$false)]
    [string]$HaloApiKey
    
)

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

# PHASE 1: Deploy Infrastructure
Write-Host "`n=== PHASE 1: Infrastructure Deployment ===" -ForegroundColor Magenta

& "$PSScriptRoot/scripts/Deploy-Infrastructure.ps1" `
    -Action $Action `
    -Subscription $Subscription `
    -Location $Location `
    -Environment $Environment

if ($LASTEXITCODE -ne 0) {
    Write-Host "Infrastructure deployment failed" -ForegroundColor Red
    exit 1
}

# Skip APIM configuration if only running specific actions
if ($Action -eq "output" -or $Action -eq "fmt" -or $Action -eq "clean") {
    exit 0
}

# PHASE 2: Deploy APIM Configuration
Write-Host "`n=== PHASE 2: APIM Configuration ==="  -ForegroundColor Magenta

& "$PSScriptRoot/scripts/Deploy-APIM-Configuration.ps1" `
    -Subscription $Subscription `
    -HaloApiKey $HaloApiKey `
    -Environment $Environment

if ($LASTEXITCODE -ne 0) {
    Write-Host "APIM configuration failed" -ForegroundColor Red
    exit 1
}
    

# Deployment Summary
Write-Host @"

============================================================
                 Deployment Summary
============================================================

"@ -ForegroundColor Cyan
Write-Success "Azure Infrastructure deployed (AI Foundry, AI Search, API Management, Storage)"
Write-Success "Terraform configuration applied successfully"
Write-Success "All Azure resources provisioned"
Write-Success "Halo API Key stored in Key Vault"

Write-Host "`n=== Next Steps ===" -ForegroundColor Cyan
Write-Host "1. Run 'cd infra; terraform output' to view resource endpoints" -ForegroundColor Gray
Write-Host "2. If the Halo API key was provided, run the terraform apply with Key Vault parameters (shown in Phase 2 output)" -ForegroundColor Gray
Write-Host "3. Configure the MCP server in APIM (see Deployment_Steps.md)" -ForegroundColor Gray
Write-Host "4. Register the MCP tool and create the agent in Microsoft Foundry (see Deployment_Steps.md)" -ForegroundColor Gray
Write-Host "5. Copy Notebooks/.env.sample to Notebooks/.env and fill in your values" -ForegroundColor Gray

Write-Host @"

============================================================
           Deployment Complete!
============================================================

"@ -ForegroundColor Green
