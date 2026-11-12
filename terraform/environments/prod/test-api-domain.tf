variable "enable_test_api_domain" {
  description = "Enable an isolated HTTPS hostname on the V2 ALB without changing production application DNS."
  type        = bool
  default     = true
}

variable "test_api_domain_name" {
  description = "Pre-cutover API test hostname; this still accesses production data."
  type        = string
  default     = "api-test.zipsai.co.kr"

  validation {
    condition     = endswith(var.test_api_domain_name, ".zipsai.co.kr") && !contains(["api.zipsai.co.kr", "www.zipsai.co.kr"], var.test_api_domain_name)
    error_message = "Use a separate test subdomain, not an existing production API or frontend hostname."
  }
}

resource "aws_route53_record" "test_api" {
  count = var.enable_v2_apps && var.enable_test_api_domain ? 1 : 0

  zone_id = data.terraform_remote_state.shared.outputs.route53_zone_id
  name    = var.test_api_domain_name
  type    = "A"
  alias {
    name                   = module.ecs.alb_dns_name
    zone_id                = module.ecs.alb_zone_id
    evaluate_target_health = true
  }
}

output "test_api_url" {
  description = "Production-data API test endpoint; not a frontend or a production DNS cutover."
  value       = var.enable_test_api_domain ? "https://${var.test_api_domain_name}" : null
}

# Public tests must not expose Actuator metrics. Private Task-IP collection is unaffected.
resource "aws_lb_listener_rule" "hide_actuator_metrics" {
  count = var.enable_v2_apps && (local.api_domain_enabled || var.enable_test_api_domain) ? 1 : 0

  listener_arn = module.ecs.https_listener_arn
  priority     = 10
  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not found"
      status_code  = "404"
    }
  }
  condition {
    path_pattern {
      values = ["/api/actuator/prometheus", "/api/actuator/metrics", "/api/actuator/metrics/*"]
    }
  }
  tags = local.common_tags
}
