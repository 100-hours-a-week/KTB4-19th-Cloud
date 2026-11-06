variable "enable_test_frontend_domain" {
  description = "Serve the V2 production frontend on a separate pre-cutover hostname."
  type        = bool
  default     = true
}

variable "test_frontend_domain_name" {
  description = "Pre-cutover frontend hostname. The connected API uses production data."
  type        = string
  default     = "prod-test.zipsai.co.kr"
  validation {
    condition     = endswith(var.test_frontend_domain_name, ".zipsai.co.kr") && !contains(["www.zipsai.co.kr", "api.zipsai.co.kr", "v2.zipsai.co.kr", "api-v2.zipsai.co.kr"], var.test_frontend_domain_name)
    error_message = "Use a separate test hostname, not an existing production or staging hostname."
  }
}

resource "aws_route53_record" "test_frontend" {
  for_each = var.enable_test_frontend_domain ? toset(["A", "AAAA"]) : toset([])

  zone_id = data.terraform_remote_state.shared.outputs.route53_zone_id
  name    = var.test_frontend_domain_name
  type    = each.value
  alias {
    name                   = module.frontend.distribution_domain_name
    zone_id                = module.frontend.distribution_hosted_zone_id
    evaluate_target_health = false
  }
}

output "test_frontend_url" {
  description = "Pre-cutover frontend; this is not an isolated test database."
  value       = var.enable_test_frontend_domain ? "https://${var.test_frontend_domain_name}" : null
}
