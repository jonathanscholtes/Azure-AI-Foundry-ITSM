variable "app_configuration_name" {
  description = "Name of the App Configuration store"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "identity_principal_id" {
  description = "Principal ID of the managed identity (App Configuration Data Reader)"
  type        = string
}

variable "deployer_principal_id" {
  description = "Principal ID of the deploying user or service principal (App Configuration Data Owner)"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
