# Prepare the final API hostname without switching the production frontend DNS.
variable "enable_production_api_domain" {
  description = "Enable the production API hostname independently of frontend DNS cutover."
  type        = bool
  default     = true
}

# Historical state migration: the former additional-SNI binding was forgotten
# when module.ecs took ownership of the listener default certificate.
# Issue #22 switched that default to the shared wildcard and detached the
# leftover unmanaged SNI binding. Keep this block for older state upgrades.
removed {
  from = aws_lb_listener_certificate.production_api
  lifecycle {
    destroy = false
  }
}

output "production_api_url" {
  value       = local.api_domain_enabled ? "https://${local.api_domain_name}" : null
  description = "Final V2 API endpoint; enabling it does not switch frontend production DNS."
}
