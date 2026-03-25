locals {
  # Naming convention
  name_prefix = "${var.project_name}-${var.environment}"

  # AI Foundry naming
  ai_account_name = "fnd-${var.project_name}-${var.environment}-${var.resource_token}"
  ai_project_name = "proj-${var.project_name}-${var.environment}-${var.resource_token}"

  # Normalize empty strings from tfvars to null (Terraform treats "" as truthy)
  halo_auth_url = var.halo_auth_url != null && var.halo_auth_url != "" ? var.halo_auth_url : null

  # Common tags for all resources
  common_tags = merge(
    var.tags,
    {
      "CreatedBy"   = "Terraform"
      "Environment" = var.environment
      "Project"     = var.project_name
    }
  )
}
