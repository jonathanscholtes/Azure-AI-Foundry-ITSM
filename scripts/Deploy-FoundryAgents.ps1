# Deploy-FoundryAgents.ps1
# Creates/versions ITSM agents in Microsoft Foundry via Python SDK.
# Agent names are written to Azure App Configuration for container app consumption.
#
# Usage:
#   .\Deploy-FoundryAgents.ps1 -AiProjectEndpoint <endpoint> -AppConfigEndpoint <endpoint>
#   .\Deploy-FoundryAgents.ps1 -AiProjectEndpoint <endpoint> -AppConfigEndpoint <endpoint> -Only kb_lookup ticket_agent

param (
    [Parameter(Mandatory = $true)]
    [string]$AiProjectEndpoint,

    [Parameter(Mandatory = $false)]
    [string]$ModelDeployment = "gpt-4.1",

    [Parameter(Mandatory = $false)]
    [string]$AppConfigEndpoint,

    [Parameter(Mandatory = $false)]
    [string]$McpServerUrl,

    [Parameter(Mandatory = $false)]
    [string]$McpServerLabel = "halo-itsm-mcp",

    [Parameter(Mandatory = $false)]
    [string]$ApimSubscriptionKey,

    # Deploy only the listed agents (e.g. "kb_lookup", "ticket_agent", "triage_agent").
    # When empty, deploys all agents.
    [Parameter(Mandatory = $false)]
    [string[]]$Only = @()
)

$ErrorActionPreference = "Stop"

Write-Host "`n=== ITSM: Deploy Foundry Agents ===" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 1. Check Python
# ---------------------------------------------------------------------------
try {
    $pythonVersion = python --version 2>&1
    Write-Host "Python found: $pythonVersion" -ForegroundColor Green
} catch {
    Write-Host "Python not found - cannot deploy agents." -ForegroundColor Red
    throw "Python is required for agent deployment."
}

# ---------------------------------------------------------------------------
# 2. Install Python dependencies
# ---------------------------------------------------------------------------
Write-Host "`nInstalling Python dependencies..." -ForegroundColor Yellow
$repoRoot = Split-Path $PSScriptRoot -Parent
pip install -r "$repoRoot\agents\requirements.txt" --quiet
if ($LASTEXITCODE -ne 0) { throw "pip install failed." }

# ---------------------------------------------------------------------------
# 3. Print configuration
# ---------------------------------------------------------------------------
Write-Host "`nAgent Configuration:" -ForegroundColor Cyan
Write-Host "  Project Endpoint   : $AiProjectEndpoint"   -ForegroundColor White
Write-Host "  Model Deployment   : $ModelDeployment"      -ForegroundColor White
Write-Host "  App Config Endpoint: $AppConfigEndpoint"    -ForegroundColor White
Write-Host "  MCP Server URL     : $McpServerUrl"         -ForegroundColor White

# ---------------------------------------------------------------------------
# 4. Run the Python provisioning script
# ---------------------------------------------------------------------------
Write-Host "`nProvisioning agents in Microsoft Foundry..." -ForegroundColor Yellow

$pythonArgs = @(
    "$repoRoot\agents\deploy.py",
    "--project-endpoint", $AiProjectEndpoint,
    "--model-deployment", $ModelDeployment
)

if ($McpServerUrl) {
    $pythonArgs += "--mcp-server-url"
    $pythonArgs += $McpServerUrl
}
if ($McpServerLabel) {
    $pythonArgs += "--mcp-server-label"
    $pythonArgs += $McpServerLabel
}
if ($ApimSubscriptionKey) {
    $pythonArgs += "--apim-subscription-key"
    $pythonArgs += $ApimSubscriptionKey
}
if ($AppConfigEndpoint) {
    $pythonArgs += "--app-config-endpoint"
    $pythonArgs += $AppConfigEndpoint
}
if ($Only.Count -gt 0) {
    $pythonArgs += "--only"
    $pythonArgs += $Only
}


python @pythonArgs

if ($LASTEXITCODE -ne 0) {
    throw "Agent deployment script failed (exit code $LASTEXITCODE)."
}

Write-Host "`n[OK] Foundry agents deployed " -ForegroundColor Green
Write-Host "`n=== Done ===" -ForegroundColor Cyan

