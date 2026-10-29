# Prepare the final API hostname without switching the production frontend DNS.
variable "enable_production_api_domain" {
  description = "Enable the production API hostname independently of frontend DNS cutover."
  type        = bool
  default     = true
}

# The production certificate is now the listener DEFAULT, owned by module.ecs.
# Drop only the former additional-SNI Terraform ownership, not the live cert.
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
