# Common deployment functions for Microsoft Foundry ITSM
# This module contains shared utilities used across deployment scripts

# PowerShell 5.1 compatibility — $IsWindows/$IsMacOS/$IsLinux are only automatic in PS 7+
if (-not (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue)) {
    $IsWindows = $true   # Windows PowerShell 5.1 only runs on Windows
    $IsMacOS   = $false
    $IsLinux   = $false
}

# Helper functions for formatted output
function Write-Title {
    param([string]$Title)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Initialize-AzureContext {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Subscription
    )
    
    Write-Host "`n=== Initializing Azure Context ===" -ForegroundColor Cyan
    
    # Configure Azure CLI settings (Windows-specific broker) — suppress experimental warnings
    if ($IsWindows) {
        az config set core.enable_broker_on_windows=false 2>&1 | Out-Null
    }
    az config set core.login_experience_v2=off 2>&1 | Out-Null
    
    # Check current authentication
    try {
        $currentAccount = az account show --query "id" -o tsv 2>$null
        if ($currentAccount) {
            Write-Host "[OK] Already authenticated" -ForegroundColor Green
        } else {
            throw "Not authenticated"
        }
    } catch {
        Write-Host "Logging into Azure..." -ForegroundColor Cyan
        az login | Out-Null
    }
    
    # Set subscription
    az account set --subscription $Subscription
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set subscription to $Subscription"
    }
    
    Write-Host "[OK] Connected to subscription: $Subscription" -ForegroundColor Green
}

function Test-RequiredTools {
    param (
        [string[]]$Tools = @("terraform", "az")
    )
    
    Write-Host "`n=== Checking Required Tools ===" -ForegroundColor Cyan
    
    $missingTools = @()
    
    # Define cross-platform installation instructions
    $installationGuide = @{
        'terraform' = @{
            'Windows' = 'winget install HashiCorp.Terraform'
            'Linux'   = 'sudo apt-get install -y terraform  (or see https://developer.hashicorp.com/terraform/install)'
            'macOS'   = 'brew install hashicorp/tap/terraform'
        }
        'az' = @{
            'Windows' = 'winget install Microsoft.AzureCLI'
            'Linux'   = 'curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash'
            'macOS'   = 'brew install azure-cli'
        }
        'python' = @{
            'Windows' = 'winget install Python.Python.3.11'
            'Linux'   = 'sudo apt-get install -y python3 python3-pip'
            'macOS'   = 'brew install python@3.11'
        }
    }
    
    # Detect platform
    $platform = if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'macOS' } else { 'Linux' }
    
    foreach ($tool in $Tools) {
        if (Get-Command $tool -ErrorAction SilentlyContinue) {
            Write-Host "[OK] $tool found" -ForegroundColor Green
        } else {
            Write-Host "[X] $tool not found" -ForegroundColor Red
            $missingTools += $tool
        }
    }
    
    if ($missingTools.Count -gt 0) {
        Write-Host "`n[X] Missing required tools: $($missingTools -join ', ')" -ForegroundColor Red
        Write-Host "`nInstallation instructions ($platform):" -ForegroundColor Yellow
        
        foreach ($tool in $missingTools) {
            if ($installationGuide.ContainsKey($tool)) {
                Write-Host "`n${tool}:" -ForegroundColor White
                Write-Host "  $($installationGuide[$tool][$platform])" -ForegroundColor Gray
            }
        }
        
        throw "Missing required tools. Please install and retry."
    }
    
    Write-Host "All required tools found`n" -ForegroundColor Green
}

function Get-ResourceToken {
    param (
        [Parameter(Mandatory=$true)]
        [string]$SubscriptionId,
        [int]$Length = 8
    )
    
    $base36Chars = "abcdefghijklmnopqrstuvwxyz123456789"
    
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $inputBytes = [System.Text.Encoding]::UTF8.GetBytes($SubscriptionId)
    $hashBytes = $sha256.ComputeHash($inputBytes)
    
    $token = ""
    for ($i = 0; $i -lt $Length; $i++) {
        $index = $hashBytes[$i % $hashBytes.Length] % $base36Chars.Length
        $token += $base36Chars[$index]
    }
    
    return $token
}

function New-SecurePassword {
    param (
        [int]$Length = 16
    )
    # Ensure minimum password length of 8
    if ($Length -lt 8) {
        $Length = 8
    }
    
    # Define character sets
    $lowercase = 'abcdefghijklmnopqrstuvwxyz'
    $uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    $numbers = '0123456789'
    
    # Ensure password contains at least one from each required category
    $password = @()
    $password += $lowercase[(Get-Random -Maximum $lowercase.Length)]
    $password += $uppercase[(Get-Random -Maximum $uppercase.Length)]
    $password += $numbers[(Get-Random -Maximum $numbers.Length)]
    
    # Fill remaining length with random characters from all sets
    $allChars = $lowercase + $uppercase + $numbers
    for ($i = $password.Count; $i -lt $Length; $i++) {
        $password += $allChars[(Get-Random -Maximum $allChars.Length)]
    }
    
    # Shuffle the password to avoid predictable pattern
    $shuffled = $password | Get-Random -Count $password.Count
    return -join $shuffled
}

function Set-KeyVaultSecret {
    param (
        [Parameter(Mandatory=$true)]
        [string]$KeyVaultName,
        
        [Parameter(Mandatory=$true)]
        [string]$SecretName,
        
        [Parameter(Mandatory=$true)]
        [string]$SecretValue
    )
    
    Write-Title "Adding Secret to Key Vault: $SecretName"
    
    try {
        az keyvault secret set `
            --vault-name $KeyVaultName `
            --name $SecretName `
            --value $SecretValue | Out-Null
        
        Write-Success "Secret '$SecretName' added to Key Vault '$KeyVaultName'"
        return $true
    } catch {
        Write-Error "Failed to set secret: $_"
        return $false
    }
}

Export-ModuleMember -Function @(
    'Write-Title',
    'Write-Success',
    'Write-Info',
    'Initialize-AzureContext',
    'Test-RequiredTools',
    'Get-ResourceToken',
    'New-SecurePassword',
    'Set-KeyVaultSecret'
)
