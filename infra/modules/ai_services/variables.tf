variable "ai_account_name" {
  description = "Name of the AI Services account"
  type        = string
}

variable "ai_project_name" {
  description = "Name of the AI Project"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "identity_id" {
  description = "ID of the managed identity"
  type        = string
}

variable "identity_principal_id" {
  description = "Principal ID of the managed identity"
  type        = string
}

variable "gpt41_capacity" {
  description = "Capacity for GPT-4.1 deployment"
  type        = number
  default     = 150
}

variable "embedding_capacity" {
  description = "Capacity for text-embedding-ada-002 deployment"
  type        = number
  default     = 120
}

variable "application_insights_id" {
  description = "Resource ID of the Application Insights instance to link to the AI project"
  type        = string
}

variable "search_endpoint" {
  description = "Endpoint URL of the Azure AI Search service"
  type        = string
}

variable "search_service_id" {
  description = "Resource ID of the Azure AI Search service for connection metadata"
  type        = string
}

variable "app_insights_instrumentation_key" {
  description = "Instrumentation key of the Application Insights instance"
  type        = string
  sensitive   = true
}
