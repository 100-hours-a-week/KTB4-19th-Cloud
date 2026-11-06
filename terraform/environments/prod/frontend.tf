locals {
  frontend_domain_name = "zipsai.co.kr"
  api_domain_name      = "api.zipsai.co.kr"
  api_domain_enabled   = var.enable_custom_domains || var.enable_production_api_domain

  frontend_certificate_arn = (var.enable_production_frontend_domain || var.enable_custom_domains || var.enable_test_frontend_domain) ? data.terraform_remote_state.shared.outputs.cloudfront_certificate_arn : null
  api_certificate_arn      = (local.api_domain_enabled || var.enable_test_api_domain) ? data.terraform_remote_state.shared.outputs.api_alb_certificate_arn : null
}

module "frontend" {
  source = "../../modules/frontend"

  enable_api_proxy = false

  name_prefix = local.name_prefix
  common_tags = local.common_tags
  bucket_name = "zipsai-prod-frontend-origin"
  domain_name = (var.enable_custom_domains || var.enable_production_frontend_domain) ? local.frontend_domain_name : (
    var.enable_test_frontend_domain ? var.test_frontend_domain_name : null
  )
  certificate_arn       = local.frontend_certificate_arn
  canonical_domain_name = var.enable_production_frontend_domain ? local.frontend_domain_name : null
  additional_domain_names = var.enable_production_frontend_domain ? concat(
    ["www.zipsai.co.kr"],
    var.enable_test_frontend_domain ? [var.test_frontend_domain_name] : []
  ) : []
  api_origin_domain_name = local.api_domain_enabled ? local.api_domain_name : (
    var.enable_test_api_domain ? var.test_api_domain_name : null
  )

  depends_on = [aws_route53_record.api]
}

resource "aws_route53_record" "frontend" {
  count = var.enable_custom_domains ? 1 : 0

  zone_id = data.terraform_remote_state.shared.outputs.route53_zone_id
  name    = local.frontend_domain_name
  type    = "A"

  alias {
    name                   = module.frontend.distribution_domain_name
    zone_id                = module.frontend.distribution_hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "frontend_ipv6" {
  count = var.enable_custom_domains ? 1 : 0

  zone_id = data.terraform_remote_state.shared.outputs.route53_zone_id
  name    = local.frontend_domain_name
  type    = "AAAA"

  alias {
    name                   = module.frontend.distribution_domain_name
    zone_id                = module.frontend.distribution_hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "api" {
  count = local.api_domain_enabled ? 1 : 0

  zone_id = data.terraform_remote_state.shared.outputs.route53_zone_id
  name    = local.api_domain_name
  type    = "A"

  alias {
    name                   = module.ecs.alb_dns_name
    zone_id                = module.ecs.alb_zone_id
    evaluate_target_health = true
  }
}
