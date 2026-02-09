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
Import-Module "$PSScriptRoot\scripts\common\DeploymentFunctions.psm1" -Force

Write-Host @"

============================================================
  Agentic Service Help Desk - Deployment Orchestrator
============================================================

"@ -ForegroundColor Cyan

# Initialize Azure context
Initialize-AzureContext -Subscription $Subscription

# PHASE 1: Deploy Infrastructure
Write-Host "`n=== PHASE 1: Infrastructure Deployment ===" -ForegroundColor Magenta

& "$PSScriptRoot\scripts\Deploy-Infrastructure.ps1" `
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

& "$PSScriptRoot\scripts\Deploy-APIM-Configuration.ps1" `
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
Write-Success "APIs, operations, policies, and tags configured via Terraform"
Write-Warning "APIM named value will be created after running the terraform apply command shown above"

Write-Host "`n=== Next Steps ===" -ForegroundColor Cyan
Write-Host "1. Use 'terraform output' in the infra/ directory to view resource details" -ForegroundColor Gray
Write-Host "2. Run the terraform apply command with Key Vault secret parameters (shown in deployment output)" -ForegroundColor Gray

Write-Host @"

============================================================
           Deployment Complete!
============================================================

"@ -ForegroundColor Green
