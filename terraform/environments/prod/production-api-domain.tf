# Prepare the final API hostname without switching the production frontend DNS.
variable "enable_production_api_domain" {
  description = "Enable the production API hostname independently of frontend DNS cutover."
  type        = bool
  default     = true
}

# Preserve the test certificate as the default during parallel validation.
resource "aws_lb_listener_certificate" "production_api" {
  count = var.enable_production_api_domain && !var.enable_custom_domains && var.enable_test_api_domain ? 1 : 0

  listener_arn    = module.ecs.https_listener_arn
  certificate_arn = aws_acm_certificate_validation.api[0].certificate_arn
}

output "production_api_url" {
  value       = local.api_domain_enabled ? "https://${local.api_domain_name}" : null
  description = "Final V2 API endpoint; enabling it does not switch frontend production DNS."
}
