# Azure AI Foundry ITSM Terraform Deployment

This Terraform project deploys a complete infrastructure for AI Foundry ITSM solution on Azure, including:

- **Resource Group** - Container for all resources
- **Azure AI Search** - Cognitive search service for LLM RAG patterns
- **API Management (APIM)** - API gateway and management platform
- **Storage Account** - Blob storage for data and artifacts
- **Container Registry** - Docker image registry for containerized workloads
- **Key Vault** - Secrets and certificate management

## Prerequisites

1. **Terraform** >= 1.0 installed
2. **Azure CLI** installed and authenticated
3. **Valid Azure Subscription**

### Installation

```bash
# Install Terraform
# Windows: https://developer.hashicorp.com/terraform/downloads
# Or use winget: winget install HashiCorp.Terraform

# Install Azure CLI
# Windows: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows

# Authenticate with Azure
az login
```

## Quick Start

### 1. Update Configuration

Edit `terraform.tfvars` and update the following:

```hcl
subscription_id = "YOUR_SUBSCRIPTION_ID"  # Required!
location        = "eastus"                 # Change as needed
environment     = "dev"                    # dev, staging, or prod
```

To find your subscription ID:
```bash
az account list --output table
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Plan the Deployment

```bash
terraform plan -out=tfplan
```

Review the planned changes to ensure they match your expectations.

### 4. Apply the Configuration

```bash
terraform apply tfplan
```

### 5. Verify the Deployment

```bash
terraform output
```

## Configuration Details

### Variables

Key variables in `variables.tf`:

| Variable | Default | Description |
|----------|---------|-------------|
| `subscription_id` | - | Azure subscription ID (required) |
| `resource_group_name` | `rg-ai-foundry-itsm` | Resource group name |
| `location` | `eastus` | Azure region |
| `search_sku` | `free` | AI Search SKU (free, basic, standard) |
| `apim_sku` | `Developer` | APIM SKU (Consumption, Developer, Basic, Standard, Premium) |
| `environment` | `dev` | Environment designation |
| `project_name` | `aifoundry` | Project identifier |

### Customization

#### Change Resource Names

In `terraform.tfvars`, modify:
```hcl
search_service_name      = "my-custom-search"
container_registry_name  = "mycustomacr"
storage_account_name     = "mystorageacct"
```

#### Change SKUs

For Production environments:

```hcl
search_sku        = "standard"    # Better performance
apim_sku          = "Standard"    # Production support
apim_sku_capacity = 2             # Multiple units
```

#### Add Tags

In `terraform.tfvars`:
```hcl
tags = {
  Environment = "production"
  Project     = "AI-Foundry-ITSM"
  ManagedBy   = "Terraform"
  CostCenter  = "12345"
}
```

## Outputs

After deployment, access resource information:

```bash
# Get all outputs
terraform output

# Get specific output
terraform output apim_gateway_url
terraform output search_service_endpoint
```

Key outputs:
- `resource_group_name` - Resource group name
- `search_service_endpoint` - AI Search service endpoint
- `apim_gateway_url` - API Management gateway URL
- `apim_portal_url` - APIM developer portal URL
- `container_registry_login_server` - ACR login server

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

Confirm by typing `yes` when prompted.

## Next Steps

### Configure Microsoft Foundry

Once the infrastructure is deployed, configure the AI Foundry project:

1. Navigate to the created resource group in Azure Portal
2. Set up AI Foundry Hub and Project
3. Connect AI Search service
4. Configure API Management APIs

### Create API Management APIs

1. Access APIM portal: `terraform output apim_portal_url`
2. Create APIs to expose your AI services
3. Configure policies, authentication, and rate limiting

### Set Up Storage

1. Create containers in the storage account
2. Upload training data, models, or configuration files
3. Configure access controls and managed identities

## Troubleshooting

### Authentication Issues

```bash
# Check current authentication
az account show

# Login again if needed
az logout
az login
```

### Terraform Lock Issues

```bash
# Remove lock file if stuck
rm .terraform.lock.hcl
terraform init
```

### Azure Resource Naming Conflicts

If resources already exist with the chosen names:
1. Update resource names in `terraform.tfvars`
2. Re-run `terraform plan`

### Free SKU Limitations

The default configuration uses free tiers. Note:
- **AI Search**: Limited queries and storage
- **APIM**: Limited throughput

Consider upgrading for production use.

## File Structure

```
.
├── main.tf              # Primary resource definitions
├── variables.tf         # Variable declarations
├── outputs.tf           # Output definitions
├── provider.tf          # Provider configuration
├── locals.tf            # Local values
├── terraform.tfvars     # Variable values (customize this)
└── README.md            # This file
```

## Best Practices

1. **State Management**
   - Consider using Azure Storage for remote state in production
   - Add `.terraform/` to `.gitignore`

2. **Security**
   - Never commit `terraform.tfvars` with real subscription IDs
   - Use Azure Key Vault for sensitive values
   - Enable Key Vault purge protection for production

3. **Cost Control**
   - Start with free/basic SKUs for development
   - Set up budget alerts in Azure
   - Regularly review unused resources

4. **Environment Separation**
   - Create separate `.tfvars` files for dev, staging, prod
   - Use workspaces: `terraform workspace new staging`

## Support and Documentation

- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure AI Search](https://learn.microsoft.com/en-us/azure/search/)
- [Azure API Management](https://learn.microsoft.com/en-us/azure/api-management/)
- [Azure Foundry](https://learn.microsoft.com/en-us/azure/ai-foundry/)

## License

This Terraform configuration is provided as-is for deploying Azure AI Foundry ITSM infrastructure.
