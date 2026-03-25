# Deploy APIM Configuration - Secrets and Named Values
# This script handles secrets deployment to Key Vault
# APIs, operations, policies, and tags are managed via Terraform in the apim_apis module

param (
    [Parameter(Mandatory=$true)]
    [string]$Subscription,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("apikey", "oauth")]
    [string]$HaloAuthMethod = "apikey",

    [Parameter(Mandatory=$false)]
    [string]$HaloApiKey,

    [Parameter(Mandatory=$false)]
    [string]$HaloClientId,

    [Parameter(Mandatory=$false)]
    [string]$HaloClientSecret,

    [Parameter(Mandatory=$false)]
    [string]$HaloAuthUrl,

    [Parameter(Mandatory=$false)]
    [string]$HaloTenant,
    
    [Parameter(Mandatory=$false)]
    [string]$Environment = "dev"
)

Set-StrictMode -Version Latest
Set-Variable -Name ErrorActionPreference -Value 'Stop'

# Import common functions
Import-Module "$PSScriptRoot/common/DeploymentFunctions.psm1" -Force

function Get-InfraOutputs {
    Write-Info "Retrieving Terraform outputs..."
    
    try {
        $outputs = & terraform -chdir="$PSScriptRoot/../infra" output -json 2>$null | ConvertFrom-Json
        
        if (-not $outputs) {
            throw "Failed to retrieve Terraform outputs"
        }
        
        return $outputs
    } catch {
        Write-Error "Could not retrieve infrastructure outputs: $_"
        return $null
    }
}

function Deploy-Secrets {
    param (
        [PSCustomObject]$Outputs,
        [string]$HaloAuthMethod,
        [string]$HaloApiKey,
        [string]$HaloClientId,
        [string]$HaloClientSecret
    )
    
    Write-Title "Deploying Secrets to Key Vault"
    
    if (-not $Outputs -or -not $Outputs.key_vault_name) {
        Write-Error "Key Vault name not found in Terraform outputs"
        return $null
    }
    
    $keyVaultName = $Outputs.key_vault_name.value
    Write-Success "Found Key Vault: $keyVaultName"
    
    if ($HaloAuthMethod -eq "oauth") {
        # OAuth mode: store client_id and client_secret
        if ([string]::IsNullOrEmpty($HaloClientId)) {
            Write-Info "No HaloClientId provided. Checking environment variable..."
            $HaloClientId = $env:HALO_CLIENT_ID
        }
        if ([string]::IsNullOrEmpty($HaloClientSecret)) {
            Write-Info "No HaloClientSecret provided. Checking environment variable..."
            $HaloClientSecret = $env:HALO_CLIENT_SECRET
        }

        if ([string]::IsNullOrEmpty($HaloClientId)) {
            Write-Info "Prompting for halo-client-id (or press Enter to skip)..."
            $secureInput = Read-Host "Enter halo-client-id" -AsSecureString
            if ($secureInput.Length -gt 0) {
                $HaloClientId = [System.Net.NetworkCredential]::new("", $secureInput).Password
            }
        }
        if ([string]::IsNullOrEmpty($HaloClientSecret)) {
            Write-Info "Prompting for halo-client-secret (or press Enter to skip)..."
            $secureInput = Read-Host "Enter halo-client-secret" -AsSecureString
            if ($secureInput.Length -gt 0) {
                $HaloClientSecret = [System.Net.NetworkCredential]::new("", $secureInput).Password
            }
        }

        if (-not [string]::IsNullOrEmpty($HaloClientId) -and -not [string]::IsNullOrEmpty($HaloClientSecret)) {
            $null = Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "halo-client-id" -SecretValue $HaloClientId
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to set halo-client-id secret"
                return $null
            }
            $null = Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "halo-client-secret" -SecretValue $HaloClientSecret
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to set halo-client-secret secret"
                return $null
            }
            Write-Success "OAuth secrets deployed successfully"
            return $keyVaultName
        } else {
            Write-Info "Skipping OAuth secrets (client_id or client_secret not provided)"
            return $keyVaultName
        }
    } else {
        # API Key mode (existing behavior)
        if ([string]::IsNullOrEmpty($HaloApiKey)) {
            Write-Info "No HaloApiKey provided. Checking environment variable..."
            $HaloApiKey = $env:HALO_API_KEY
        }
        
        if ([string]::IsNullOrEmpty($HaloApiKey)) {
            Write-Info "Prompting for halo-api-key (or press Enter to skip)..."
            $secureInput = Read-Host "Enter halo-api-key" -AsSecureString
            if ($secureInput.Length -gt 0) {
                $HaloApiKey = [System.Net.NetworkCredential]::new("", $secureInput).Password
            }
        }
        
        if (-not [string]::IsNullOrEmpty($HaloApiKey)) {
            $null = Set-KeyVaultSecret -KeyVaultName $keyVaultName -SecretName "halo-api-key" -SecretValue $HaloApiKey
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to set halo-api-key secret"
                return $null
            }
            
            Write-Success "Secrets deployed successfully"
            return $keyVaultName
        } else {
            Write-Info "Skipping halo-api-key (no secret provided)"
            return $keyVaultName
        }
    }
}

function Get-KeyVaultSecretUri {
    param (
        [string]$KeyVaultName,
        [string]$SecretName
    )
    
    Write-Info "Constructing Key Vault secret URI..."
    
    # Construct the versionless URI directly — no network call required.
    # APIM resolves versionless URIs to the latest secret version automatically.
    $secretUri = "https://${KeyVaultName}.vault.azure.net/secrets/${SecretName}"
    Write-Success "Secret URI: $secretUri"
    return $secretUri
}

function Update-TerraformForNamedValue {
    param (
        [string]$HaloAuthMethod,
        [string]$IdentityClientId,
        [string]$SecretUri,
        [string]$ClientIdSecretUri,
        [string]$ClientSecretSecretUri,
        [string]$HaloAuthUrl
    )
    
    Write-Title "Creating APIM Named Value via Terraform"
    
    Write-Info "Auth method: $HaloAuthMethod"
    Write-Info "Identity Client ID: $IdentityClientId"
    
    $infraDir = Join-Path $PSScriptRoot "../infra"
    
    Write-Info "Running targeted Terraform apply for APIM named value..."

    if ($HaloAuthMethod -eq "oauth") {
        Write-Info "Client ID Secret URI: $ClientIdSecretUri"
        Write-Info "Client Secret Secret URI: $ClientSecretSecretUri"
        Write-Info "Auth URL: $HaloAuthUrl"

        & terraform -chdir="$infraDir" apply `
            -var="halo_client_id_secret_identifier=$ClientIdSecretUri" `
            -var="halo_client_secret_secret_identifier=$ClientSecretSecretUri" `
            -var="identity_client_id=$IdentityClientId" `
            -auto-approve `
            -target="module.apim"
    } else {
        Write-Info "Secret URI: $SecretUri"

        & terraform -chdir="$infraDir" apply `
            -var="key_vault_secret_identifier=$SecretUri" `
            -var="identity_client_id=$IdentityClientId" `
            -auto-approve `
            -target="module.apim"
    }
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "APIM named values created successfully"
        return $true
    } else {
        Write-Error "Failed to create APIM named value"
        return $false
    }
}

# Main execution
try {
    Write-Host "`n=== PHASE 2: Secrets & APIM Configuration ===" -ForegroundColor Magenta
    
    # Get infrastructure outputs
    $outputs = Get-InfraOutputs
    if (-not $outputs) {
        Write-Error "Failed to retrieve infrastructure outputs"
        exit 1
    }
    
    # Deploy secrets
    $keyVaultName = Deploy-Secrets -Outputs $outputs -HaloAuthMethod $HaloAuthMethod -HaloApiKey $HaloApiKey -HaloClientId $HaloClientId -HaloClientSecret $HaloClientSecret
    if (-not $keyVaultName) {
        Write-Error "Failed to deploy secrets"
        exit 1
    }
    
    if (-not $outputs.managed_identity_client_id -or [string]::IsNullOrEmpty($outputs.managed_identity_client_id.value)) {
        Write-Error "managed_identity_client_id not found in Terraform outputs. Run 'terraform output' to verify."
        exit 1
    }
    
    $identityClientId = $outputs.managed_identity_client_id.value

    if ($HaloAuthMethod -eq "oauth") {
        # Construct secret URIs for client_id and client_secret
        $clientIdSecretUri = Get-KeyVaultSecretUri -KeyVaultName $keyVaultName -SecretName "halo-client-id"
        $clientSecretSecretUri = Get-KeyVaultSecretUri -KeyVaultName $keyVaultName -SecretName "halo-client-secret"

        Update-TerraformForNamedValue `
            -HaloAuthMethod "oauth" `
            -IdentityClientId $identityClientId `
            -ClientIdSecretUri $clientIdSecretUri `
            -ClientSecretSecretUri $clientSecretSecretUri `
            -HaloAuthUrl $HaloAuthUrl
    } else {
        # Construct the secret URI locally — no network call needed.
        $secretUri = Get-KeyVaultSecretUri -KeyVaultName $keyVaultName -SecretName "halo-api-key"

        Update-TerraformForNamedValue `
            -HaloAuthMethod "apikey" `
            -IdentityClientId $identityClientId `
            -SecretUri $secretUri
    }
    
    Write-Success "Secrets deployment completed successfully"
    exit 0
}
catch {
    Write-Error "Secrets deployment failed: $_"
    exit 1
}
