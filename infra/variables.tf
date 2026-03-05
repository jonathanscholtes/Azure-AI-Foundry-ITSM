variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-ai-foundry-itsm"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus2"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "resource_token" {
  description = "Resource token for unique naming"
  type        = string
  default     = "token"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "aifoundry"
}

# Managed Identity Variables
variable "managed_identity_name" {
  description = "Name of the user-assigned managed identity for all services"
  type        = string
  default     = "id-ai-foundry-main"
}

# Application Insights Variables
variable "app_insights_name" {
  description = "Name of Application Insights"
  type        = string
  default     = "appi-ai-foundry"
}

# AI Services Variables
variable "ai_services_deployment_gpt41_capacity" {
  description = "Capacity for GPT-4.1 deployment"
  type        = number
  default     = 150
}

variable "ai_services_deployment_embedding_capacity" {
  description = "Capacity for text-embedding-ada-002 deployment"
  type        = number
  default     = 120
}

# AI Search Variables
variable "search_service_name" {
  description = "Name of the AI Search service"
  type        = string
  default     = "aisearch-foundry"
}

variable "search_sku" {
  description = "SKU for AI Search service"
  type        = string
  default     = "free"

  validation {
    condition     = contains(["free", "basic", "standard", "standard2", "standard3", "storage_optimized_l1", "storage_optimized_l2"], var.search_sku)
    error_message = "Search SKU must be a valid value."
  }
}

# API Management Variables
variable "apim_publisher_name" {
  description = "Publisher name for API Management"
  type        = string
  default     = "Microsoft Foundry ITSM"
}

variable "apim_publisher_email" {
  description = "Publisher email for API Management"
  type        = string
  default     = "admin@aifoundry.com"
}

variable "halo_base_url" {
  description = "Base URL of the Halo ITSM API (e.g., https://yourinstance.haloitsm.com/api)"
  type        = string

  validation {
    condition     = can(regex("^https://", var.halo_base_url))
    error_message = "halo_base_url must start with 'https://' and point to your Halo ITSM API endpoint."
  }
}

variable "apim_sku" {
  description = "SKU for API Management"
  type        = string
  default     = "Consumption"

  validation {
    condition     = contains(["Consumption", "Developer", "Basic", "Standard", "Premium"], var.apim_sku)
    error_message = "APIM SKU must be a valid value."
  }
}

variable "apim_sku_capacity" {
  description = "Capacity for API Management"
  type        = number
  default     = 1
}

# Storage Account Variables
variable "storage_account_name" {
  description = "Name of the storage account"
  type        = string
  default     = "stoaifoundryitsm"
}

variable "storage_account_tier" {
  description = "Storage account tier"
  type        = string
  default     = "Standard"
}

variable "storage_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
}

# Key Vault Variables
variable "key_vault_name" {
  description = "Name of the Key Vault"
  type        = string
  default     = "kvfoundryitsm"
}

variable "enable_purge_protection" {
  description = "Enable purge protection for Key Vault"
  type        = bool
  default     = false
}

# Container Registry Variables
variable "container_registry_name" {
  description = "Name of the Container Registry"
  type        = string
  default     = "acraifoundryitsm"
}

variable "container_registry_sku" {
  description = "SKU for Container Registry"
  type        = string
  default     = "Basic"
}

# APIM Named Value Variables (for Key Vault secret reference)
variable "key_vault_secret_identifier" {
  description = "Key Vault secret identifier URI for halo-api-key (only set after secret is pushed)"
  type        = string
  default     = null
}

variable "identity_client_id" {
  description = "Client ID of the managed identity for accessing Key Vault secrets in APIM (only set after secret is pushed)"
  type        = string
  default     = null
}

# Tagging
variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "Microsoft-Foundry-ITSM"
    ManagedBy   = "Terraform"
  }
}
