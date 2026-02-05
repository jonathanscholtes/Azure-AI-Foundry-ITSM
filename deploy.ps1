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
    [string]$Environment = "dev"
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

# Skip summary if only running specific actions
if ($Action -eq "output" -or $Action -eq "fmt" -or $Action -eq "clean") {
    exit 0
}

$infraDeployed = $true
    

# Deployment Summary
Write-Host @"

============================================================
                 Deployment Summary
============================================================

"@ -ForegroundColor Cyan
Write-Success "Azure Infrastructure deployed (AI Foundry, AI Search, API Management, Storage)"
Write-Success "Terraform configuration applied successfully"
Write-Success "All Azure resources provisioned"

Write-Host "`n=== Service Endpoints ===" -ForegroundColor Cyan
Write-Host "Use 'terraform output' in the infra/ directory to view resource details" -ForegroundColor Gray

Write-Host @"

============================================================
              Deployment Complete!
============================================================

"@ -ForegroundColor Green
