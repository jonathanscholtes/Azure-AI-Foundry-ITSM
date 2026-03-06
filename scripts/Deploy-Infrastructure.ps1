# Deploy Azure Infrastructure using Terraform
# This script deploys all Azure resources (AI Foundry, AI Search, API Management, Storage, etc.)

param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("init", "validate", "plan", "apply", "all", "destroy", "output", "fmt", "clean")]
    [string]$Action,
    
    [Parameter(Mandatory=$true)]
    [string]$Subscription,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus2",
    
    [Parameter(Mandatory=$false)]
    [string]$Environment = "dev",

    [Parameter(Mandatory=$false)]
    [string]$HaloBaseUrl
)

# PowerShell 5.1 compatibility — $IsWindows/$IsMacOS/$IsLinux are only automatic in PS 7+
if (-not (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue)) {
    $IsWindows = $true   # Windows PowerShell 5.1 only runs on Windows
    $IsMacOS   = $false
    $IsLinux   = $false
}

Set-StrictMode -Version Latest
Set-Variable -Name ErrorActionPreference -Value 'Stop'

# Import common functions
Import-Module "$PSScriptRoot/common/DeploymentFunctions.psm1" -Force

function Get-SubscriptionId {
    # Retrieve the current subscription ID (auth already handled by orchestrator)
    $subId = az account show --query "id" -o tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($subId)) {
        Write-Error "Not authenticated or no subscription set. Ensure the orchestrator ran Initialize-AzureContext first."
        return $null
    }
    Write-Success "Using subscription: $subId"
    return $subId
}



function New-TerraformVarsFile {
    param(
        [string]$SubscriptionId,
        [string]$Location,
        [string]$Environment,
        [string]$HaloBaseUrl,
        [string]$OutputPath = "."
    )
    
    Write-Title "Generating terraform.tfvars"
    
    try {
        # Get absolute path
        $absolutePath = (Resolve-Path -Path $OutputPath -ErrorAction Stop).Path
        Write-Info "Target directory: $absolutePath"
        
        # Verify directory exists
        if (-not (Test-Path -Path $absolutePath -PathType Container)) {
            Write-Error "Output directory does not exist: $absolutePath"
            return $false
        }
        
        $resourceToken = Get-ResourceToken -SubscriptionId $SubscriptionId
        $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
        
        # Load template
        $templatePath = Join-Path $PSScriptRoot "../infra/terraform.tfvars.tpl"
        if (-not (Test-Path $templatePath)) {
            Write-Error "Template not found: $templatePath"
            return $false
        }
        
        Write-Info "Loading template from: $templatePath"
        $content = Get-Content -Path $templatePath -Raw
        
        # Replace variables using safe replacements
        $content = $content -replace '\$\{SubscriptionId\}', $SubscriptionId
        $content = $content -replace '\$\{Location\}', $Location
        $content = $content -replace '\$\{Environment\}', $Environment
        $content = $content -replace '\$\{ResourceToken\}', $resourceToken
        $content = $content -replace '\$\{Timestamp\}', $timestamp
        $content = $content -replace '\$\{HaloBaseUrl\}', $HaloBaseUrl
        
        $tfvarsPath = Join-Path -Path $absolutePath -ChildPath "terraform.tfvars"
        Set-Content -Path $tfvarsPath -Value $content -Encoding UTF8 -Force -ErrorAction Stop
        
        if (Test-Path -Path $tfvarsPath) {
            Write-Success "terraform.tfvars created at: $tfvarsPath"
            Write-Info "Resource token: $resourceToken"
            return $true
        } else {
            Write-Error "Failed to create terraform.tfvars"
            return $false
        }
    }
    catch {
        Write-Error "Error creating terraform.tfvars: $_"
        return $false
    }
}

function Test-Prerequisites {
    Write-Title "Checking Prerequisites"
    
    $missingTools = @()
    
    # Check Terraform
    if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
        $missingTools += "Terraform"
    } else {
        $tfVersion = terraform --version
        Write-Success "Terraform installed"
        Write-Host $tfVersion[0] -ForegroundColor Gray
    }
    
    # Check Azure CLI
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        $missingTools += "Azure CLI"
    } else {
        $azVersion = az --version | Select-Object -First 1
        Write-Success "Azure CLI installed"
    }
    
    # Check Azure authentication
    try {
        $account = az account show --output json | ConvertFrom-Json
        Write-Success "Azure authentication verified"
        Write-Host "Subscription: $($account.name) ($($account.id.Substring(0, 8))...)" -ForegroundColor Gray
    } catch {
        $missingTools += "Azure CLI authentication (Run 'az login')"
    }
    
    if ($missingTools.Count -gt 0) {
        Write-Error "Missing prerequisites:"
        $missingTools | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        exit 1
    }
    
    Write-Success "All prerequisites met"
    return $true
}

function Initialize-Terraform {
    Write-Title "Initializing Terraform"
    
    terraform init
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Terraform initialized successfully"
        return $true
    } else {
        Write-Error "Terraform initialization failed"
        return $false
    }
}

# Main execution
Write-Title "Microsoft Foundry ITSM - Infrastructure Deployment"

# Check prerequisites
Write-Info "Checking prerequisites..."
if (-not (Test-Prerequisites)) {
    Write-Error "Prerequisites check failed"
    exit 1
}

# Handle destroy action
if ($Action -eq "destroy") {
    $infraDir = Join-Path $PSScriptRoot "../infra"
    Set-Location -Path $infraDir

    Write-Title "Destroying Resources"
    Write-Host "WARNING: All resources created by Terraform will be permanently deleted!" -ForegroundColor Red

    Write-Host ""
    $confirmation = Read-Host "Type 'yes' to confirm resource deletion"
    if ($confirmation -ne "yes") {
        Write-Host "Destruction cancelled" -ForegroundColor Yellow
        exit 0
    }

    Write-Info "Generating destruction plan..."
    Write-Host ""
    terraform plan -destroy

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to generate destruction plan" -ForegroundColor Red
        exit 1
    }

    Write-Host ""
    Write-Info "Destroying infrastructure..."
    terraform destroy -auto-approve

    if ($LASTEXITCODE -eq 0) {
        Write-Success "Resources destroyed successfully"
        exit 0
    } else {
        Write-Host "ERROR: Destruction failed" -ForegroundColor Red
        exit 1
    }
}

# Get subscription ID (auth already set by orchestrator's Initialize-AzureContext)
if ($Action -in @("init", "plan", "apply", "all", "validate")) {
    Write-Info "Preparing for deployment action: $Action"
    $subscriptionId = Get-SubscriptionId
    if (-not $subscriptionId) {
        Write-Error "Failed to determine subscription. Was Initialize-AzureContext called?"
        exit 1
    }
}

# Change to infra directory
$infraDir = Join-Path $PSScriptRoot "../infra"
Write-Info "Changing to infrastructure directory: $infraDir"
if (-not (Test-Path $infraDir)) {
    Write-Error "Infrastructure directory not found: $infraDir"
    exit 1
}

Set-Location -Path $infraDir

# Generate terraform.tfvars now that we're in the infra directory
if ($Action -in @("init", "plan", "apply", "all", "validate")) {
    Write-Info "Generating terraform.tfvars..."
    if (-not (New-TerraformVarsFile -SubscriptionId $subscriptionId -Location $Location -Environment $Environment -HaloBaseUrl $HaloBaseUrl -OutputPath ".")) {
        Write-Error "Failed to generate terraform.tfvars"
        exit 1
    }
}

# Execute based on action
Write-Info "Executing terraform action: $Action"

switch ($Action.ToLower()) {
    "init" {
        Write-Title "Initializing Terraform"
        terraform init 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Terraform initialization failed"
            exit 1
        }
        Write-Success "Terraform initialized successfully"
    }
    "validate" {
        Write-Title "Validating Terraform Configuration"
        Initialize-Terraform
        if ($LASTEXITCODE -ne 0) { exit 1 }
        
        terraform validate 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Configuration validation failed"
            exit 1
        }
        Write-Success "Configuration is valid"
    }
    "plan" {
        Write-Title "Planning Terraform Deployment"
        Initialize-Terraform
        if ($LASTEXITCODE -ne 0) { exit 1 }
        
        terraform validate 2>&1
        if ($LASTEXITCODE -ne 0) { exit 1 }
        
        Write-Info "Generating execution plan..."
        terraform plan -out=tfplan 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Plan creation failed"
            exit 1
        }
        Write-Success "Plan created successfully"
    }
    "apply" {
        Write-Title "Applying Terraform Configuration"
        Initialize-Terraform
        if ($LASTEXITCODE -ne 0) { exit 1 }
        
        terraform validate 2>&1
        if ($LASTEXITCODE -ne 0) { exit 1 }
        
        terraform plan -out=tfplan 2>&1
        if ($LASTEXITCODE -ne 0) { exit 1 }
        
        Write-Warning "This will create/modify Azure resources"
        Write-Host "Applying infrastructure changes..." -ForegroundColor Cyan
        Write-Host "This may take 15-30 minutes (APIM deployment is slow)..." -ForegroundColor Cyan
        
        $maxRetries = 3
        $retryCount = 0
        $applySuccess = $false
        
        while ($retryCount -lt $maxRetries -and -not $applySuccess) {
            $retryCount++
            
            # Re-generate plan before each attempt (plan is consumed/invalidated after apply)
            if ($retryCount -gt 1) {
                Write-Info "Re-planning before retry..."
                terraform plan -out=tfplan 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Error "Failed to re-plan before retry attempt $retryCount"
                    exit 1
                }
            }
            
            Write-Host ""
            Write-Host "Applying... (Attempt $retryCount of $maxRetries)" -ForegroundColor Yellow
            
            terraform apply tfplan 2>&1
            if ($LASTEXITCODE -eq 0) {
                $applySuccess = $true
                Write-Success "Deployment applied successfully"
                terraform output 2>&1
            } else {
                if ($retryCount -lt $maxRetries) {
                    Write-Host "Deployment attempt $retryCount failed. Waiting 30 seconds before retry..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 30
                } else {
                    Write-Error "Deployment failed after $maxRetries attempts"
                    exit 1
                }
            }
        }
    }
    "all" {
        Write-Title "Full Terraform Deployment"
        
        # Init
        Write-Info "Step 1/4: Initializing..."
        terraform init 2>&1
        if ($LASTEXITCODE -ne 0) { exit 1 }
        
        # Validate
        Write-Info "Step 2/4: Validating..."
        terraform validate 2>&1
        if ($LASTEXITCODE -ne 0) { exit 1 }
        
        # Plan
        Write-Info "Step 3/4: Planning..."
        terraform plan -out=tfplan 2>&1
        if ($LASTEXITCODE -ne 0) { exit 1 }
        
        # Apply with retries
        Write-Warning "Step 4/4: Applying infrastructure changes..."
        Write-Host "This may take 15-30 minutes (APIM deployment is slow)..." -ForegroundColor Cyan
        
        $maxRetries = 3
        $retryCount = 0
        $applySuccess = $false
        
        while ($retryCount -lt $maxRetries -and -not $applySuccess) {
            $retryCount++
            
            # Re-generate plan before each attempt (plan is consumed/invalidated after apply)
            if ($retryCount -gt 1) {
                Write-Info "Re-planning before retry..."
                terraform plan -out=tfplan 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Error "Failed to re-plan before retry attempt $retryCount"
                    exit 1
                }
            }
            
            Write-Host ""
            Write-Host "Applying... (Attempt $retryCount of $maxRetries)" -ForegroundColor Yellow
            
            terraform apply tfplan 2>&1
            if ($LASTEXITCODE -eq 0) {
                $applySuccess = $true
                Write-Success "Full deployment completed successfully"
                terraform output 2>&1
            } else {
                if ($retryCount -lt $maxRetries) {
                    Write-Host "Deployment attempt $retryCount failed. Waiting 30 seconds before retry..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 30
                } else {
                    Write-Error "Deployment failed after $maxRetries attempts"
                    exit 1
                }
            }
        }
    }
    "output" {
        Write-Title "Deployment Outputs"
        terraform output 2>&1
    }
    "fmt" {
        Write-Title "Formatting Terraform Code"
        terraform fmt -recursive 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Code formatted"
        } else {
            Write-Error "Code formatting failed"
            exit 1
        }
    }
    "clean" {
        Write-Title "Cleaning Local State"
        Write-Warning "This will remove local Terraform files!"
        
        $confirmation = Read-Host "Type 'yes' to confirm"
        if ($confirmation -eq "yes") {
            Write-Info "Removing Terraform state files and cache..."
            Remove-Item -Path ".terraform" -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path ".terraform.lock.hcl" -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "tfplan" -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "*.tfstate*" -Force -ErrorAction SilentlyContinue
            Write-Success "State cleaned"
        } else {
            Write-Host "Clean cancelled" -ForegroundColor Yellow
        }
    }
    default {
        Write-Error "Unknown action: $Action"
        exit 1
    }
}

Write-Success "Action '$Action' completed successfully"
exit 0
