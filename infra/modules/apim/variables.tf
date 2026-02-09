variable "apim_name" {
  description = "Name of API Management service"
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

variable "publisher_name" {
  description = "Publisher name for API Management"
  type        = string
  default     = "API Publisher"
}

variable "publisher_email" {
  description = "Publisher email for API Management"
  type        = string
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
  description = "Capacity for API Management (not used for Consumption)"
  type        = number
  default     = 1
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
