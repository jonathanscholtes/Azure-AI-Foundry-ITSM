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

# PowerShell 5.1 compatibility - $IsWindows/$IsMacOS/$IsLinux are only automatic in PS 7+
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

function Invoke-TerraformApplyWithRetry {
    param(
        [string]$SuccessMessage = "Deployment applied successfully",
        [int]$MaxRetries = 3
    )

    $retryCount = 0
    $applySuccess = $false

    while ($retryCount -lt $MaxRetries -and -not $applySuccess) {
        $retryCount++
        Write-Host ""
        Write-Host "Applying... (Attempt $retryCount of $MaxRetries)" -ForegroundColor Yellow

        # Re-plan on retries to avoid "Saved plan is stale" error.
        # Use -refresh=false to skip the APIM management-plane state refresh —
        # the Developer SKU endpoint returns 422 during platform upgrades.
        if ($retryCount -gt 1) {
            Write-Info "Refreshing Azure CLI token before retry..."
            az account get-access-token --output none 2>$null

            Write-Info "Re-planning with -refresh=false (skips APIM endpoint)..."
            $planAttempt = 0
            $planOk = $false
            while ($planAttempt -lt 3 -and -not $planOk) {
                $planAttempt++
                terraform plan -refresh=false -out=tfplan
                if ($LASTEXITCODE -eq 0) {
                    $planOk = $true
                } elseif ($planAttempt -lt 3) {
                    Write-Host "Re-plan attempt $planAttempt failed. Waiting 90 seconds..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 90
                }
            }
            if (-not $planOk) {
                Write-Host "Re-plan failed after 3 attempts" -ForegroundColor Red
                exit 1
            }
        }

        terraform apply tfplan
        if ($LASTEXITCODE -eq 0) {
            $applySuccess = $true
            Write-Success $SuccessMessage
            terraform output
        } else {
            if ($retryCount -lt $MaxRetries) {
                Write-Host "Deployment attempt $retryCount failed. Waiting 120 seconds before retry..." -ForegroundColor Yellow
                Start-Sleep -Seconds 120
            } else {
                Write-Host "Deployment failed after $MaxRetries attempts" -ForegroundColor Red
                exit 1
            }
        }
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

    # Resolve subscription ID for fallback RG deletion
    $subscriptionId = az account show --query id -o tsv 2>$null

    Write-Title "Destroying Resources"
    Write-Host "WARNING: All resources created by Terraform will be permanently deleted!" -ForegroundColor Red

    Write-Host ""
    $confirmation = Read-Host "Type 'yes' to confirm resource deletion"
    if ($confirmation -ne "yes") {
        Write-Host "Destruction cancelled" -ForegroundColor Yellow
        exit 0
    }

    # Retry plan-destroy because APIM management endpoint can return 422/500
    # during platform upgrades.
    Write-Info "Generating destruction plan..."
    Write-Host ""

    $planAttempt = 0
    $planSuccess = $false
    while ($planAttempt -lt 5 -and -not $planSuccess) {
        $planAttempt++
        Write-Host "Destruction plan attempt $planAttempt of 5..." -ForegroundColor Yellow
        az account get-access-token --output none 2>$null
        terraform plan -destroy
        if ($LASTEXITCODE -eq 0) {
            $planSuccess = $true
        } elseif ($planAttempt -lt 5) {
            $waitSeconds = 60 * $planAttempt
            Write-Host "Destruction plan attempt $planAttempt failed (APIM endpoint may be down). Waiting $waitSeconds seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds $waitSeconds
        }
    }
    if (-not $planSuccess) {
        Write-Host "ERROR: Failed to generate destruction plan after 5 attempts" -ForegroundColor Red
        exit 1
    }

    Write-Host ""
    Write-Info "Destroying infrastructure..."

    $maxDestroyRetries = 3
    $destroyCount = 0
    $destroySuccess = $false

    while ($destroyCount -lt $maxDestroyRetries -and -not $destroySuccess) {
        $destroyCount++
        Write-Host "Destroy attempt $destroyCount of $maxDestroyRetries..." -ForegroundColor Yellow

        terraform destroy -auto-approve

        if ($LASTEXITCODE -eq 0) {
            $destroySuccess = $true
            Write-Success "Resources destroyed successfully"
        } elseif ($destroyCount -lt $maxDestroyRetries) {
            $waitSeconds = 60 * $destroyCount
            Write-Host "Destroy attempt $destroyCount failed (APIM management endpoint may be down). Waiting $waitSeconds seconds before retry..." -ForegroundColor Yellow
            Start-Sleep -Seconds $waitSeconds
            az account get-access-token --output none 2>$null
        }
    }

    if (-not $destroySuccess) {
        Write-Host ""
        Write-Host "Terraform destroy failed after $maxDestroyRetries attempts." -ForegroundColor Yellow
        Write-Host "Falling back: removing APIM resources from state and deleting the resource group directly." -ForegroundColor Yellow
        Write-Host ""

        # Remove all APIM resources from Terraform state so the next destroy
        # does not attempt to call the broken management-plane delete endpoint.
        $apimStateResources = & { $ErrorActionPreference = 'SilentlyContinue'; terraform state list 2>&1 } |
            Where-Object { $_ -is [string] -and $_ -match 'apim' }
        foreach ($res in $apimStateResources) {
            Write-Host "  Removing from state: $res" -ForegroundColor Gray
            & { $ErrorActionPreference = 'SilentlyContinue'; terraform state rm $res 2>&1 } | Out-Null
        }

        # Delete the resource group directly - ARM cascade-deletes all child
        # resources including APIM without going through the management endpoint.
        $resourceToken = Get-ResourceToken -SubscriptionId $subscriptionId
        $resourceGroupName = "rg-aifoundry-$Environment-$resourceToken"
        Write-Host ""
        Write-Host "Deleting resource group '$resourceGroupName' (this may take 10-20 minutes)..." -ForegroundColor Yellow
        az group delete --name $resourceGroupName --yes
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: Resource group deletion failed." -ForegroundColor Red
            Write-Host "Delete '$resourceGroupName' manually in the Azure Portal, then re-run -Destroy to clean Terraform state." -ForegroundColor Red
            exit 1
        }

        # Purge any soft-deleted APIM instances left behind by the resource group deletion.
        # az group delete soft-deletes APIM rather than hard-deleting it, and Terraform's
        # purge_soft_delete_on_destroy cannot act because APIM was already removed from state.
        Write-Host ""
        Write-Host "Purging soft-deleted APIM instances in $Location..." -ForegroundColor Yellow
        $deletedApims = az rest --method get `
            --url "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.ApiManagement/locations/$Location/deletedservices?api-version=2022-08-01" `
            2>$null | ConvertFrom-Json
        if ($deletedApims -and $deletedApims.value) {
            foreach ($apim in $deletedApims.value) {
                $apimName = $apim.name
                Write-Host "  Purging APIM: $apimName" -ForegroundColor Gray
                az rest --method delete `
                    --url "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.ApiManagement/locations/$Location/deletedservices/$($apimName)?api-version=2022-08-01" `
                    2>$null | Out-Null
            }
            Write-Host "  APIM purge requests submitted (purges complete asynchronously)" -ForegroundColor Gray
        } else {
            Write-Host "  No soft-deleted APIM instances found" -ForegroundColor Gray
        }

        # Final terraform destroy: all Azure resources are gone, so Terraform
        # will see 404s, mark everything as destroyed, and clean the state file.
        Write-Host ""
        Write-Host "Flushing remaining Terraform state entries..." -ForegroundColor Yellow
        & { $ErrorActionPreference = 'SilentlyContinue'; terraform destroy -auto-approve 2>&1 } |
            ForEach-Object { Write-Host $_ }

        Write-Success "Resources destroyed via resource group deletion fallback"
    }

    exit 0
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

# Change to infra directory (restore on exit via finally block)
$infraDir = Join-Path $PSScriptRoot "../infra"
Write-Info "Changing to infrastructure directory: $infraDir"
if (-not (Test-Path $infraDir)) {
    Write-Error "Infrastructure directory not found: $infraDir"
    exit 1
}

Push-Location -Path $infraDir

try {

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
        terraform init
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
        
        terraform validate
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
        
        terraform validate
        if ($LASTEXITCODE -ne 0) { exit 1 }
        
        # Plan — retry because APIM Developer SKU management endpoint can
        # return 422 transiently during or after platform maintenance.
        $planAttempt = 0
        $planSuccess = $false
        while ($planAttempt -lt 3 -and -not $planSuccess) {
            $planAttempt++
            Write-Info "Generating execution plan (attempt $planAttempt)..."
            az account get-access-token --output none 2>$null
            terraform plan -out=tfplan
            if ($LASTEXITCODE -eq 0) {
                $planSuccess = $true
            } elseif ($planAttempt -lt 3) {
                Write-Host "Plan attempt $planAttempt failed. Waiting 90 seconds for APIM endpoint to stabilize..." -ForegroundColor Yellow
                Start-Sleep -Seconds 90
            }
        }
        if (-not $planSuccess) {
            Write-Host "Plan creation failed after 3 attempts" -ForegroundColor Red
            exit 1
        }
        Write-Success "Plan created successfully"
    }
    "apply" {
        Write-Title "Applying Terraform Configuration"
        Initialize-Terraform
        if ($LASTEXITCODE -ne 0) { exit 1 }
        
        terraform validate
        if ($LASTEXITCODE -ne 0) { exit 1 }
        
        # Plan — retry because APIM Developer SKU management endpoint can
        # return 422 transiently during or after platform maintenance.
        $planAttempt = 0
        $planSuccess = $false
        while ($planAttempt -lt 3 -and -not $planSuccess) {
            $planAttempt++
            Write-Info "Generating execution plan (attempt $planAttempt)..."
            az account get-access-token --output none 2>$null
            terraform plan -out=tfplan
            if ($LASTEXITCODE -eq 0) {
                $planSuccess = $true
            } elseif ($planAttempt -lt 3) {
                Write-Host "Plan attempt $planAttempt failed. Waiting 90 seconds for APIM endpoint to stabilize..." -ForegroundColor Yellow
                Start-Sleep -Seconds 90
            }
        }
        if (-not $planSuccess) {
            Write-Host "Plan creation failed after 3 attempts" -ForegroundColor Red
            exit 1
        }
        
        Write-Warning "This will create/modify Azure resources"
        Write-Host "Applying infrastructure changes..." -ForegroundColor Cyan
        Write-Host "This may take up to 90 minutes (APIM Developer SKU is slow to provision)..." -ForegroundColor Cyan
        Invoke-TerraformApplyWithRetry -SuccessMessage "Deployment applied successfully"
    }
    "all" {
        Write-Title "Full Terraform Deployment"
        
        # Init
        Write-Info "Step 1/4: Initializing..."
        terraform init
        if ($LASTEXITCODE -ne 0) { exit 1 }
        
        # Validate
        Write-Info "Step 2/4: Validating..."
        terraform validate
        if ($LASTEXITCODE -ne 0) { exit 1 }
        
        # Plan — retry because APIM Developer SKU management endpoint can
        # return 422 transiently during or after platform maintenance.
        $planAttempt = 0
        $planSuccess = $false
        while ($planAttempt -lt 3 -and -not $planSuccess) {
            $planAttempt++
            Write-Info "Step 3/4: Planning (attempt $planAttempt)..."
            az account get-access-token --output none 2>$null
            terraform plan -out=tfplan
            if ($LASTEXITCODE -eq 0) {
                $planSuccess = $true
            } elseif ($planAttempt -lt 3) {
                Write-Host "Plan attempt $planAttempt failed. Waiting 90 seconds for APIM endpoint to stabilize..." -ForegroundColor Yellow
                Start-Sleep -Seconds 90
            }
        }
        if (-not $planSuccess) {
            Write-Host "Plan creation failed after 3 attempts" -ForegroundColor Red
            exit 1
        }
        
        # Apply with retry for token expiry during long APIM provisioning
        Write-Warning "Step 4/4: Applying infrastructure changes..."
        Write-Host "This may take up to 90 minutes (APIM Developer SKU is slow to provision)..." -ForegroundColor Cyan
        Invoke-TerraformApplyWithRetry -SuccessMessage "Full deployment completed successfully"
    }
    "output" {
        Write-Title "Deployment Outputs"
        terraform output
    }
    "fmt" {
        Write-Title "Formatting Terraform Code"
        terraform fmt -recursive
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

} finally {
    Pop-Location
}

Write-Success "Action '$Action' completed successfully"
exit 0
