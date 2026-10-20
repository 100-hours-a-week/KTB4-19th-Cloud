locals {
  frontend_domain_name = "zipsai.co.kr"
  api_domain_name      = "api.zipsai.co.kr"
  api_domain_enabled   = var.enable_custom_domains || var.enable_production_api_domain

  frontend_certificate_arn = var.enable_custom_domains ? aws_acm_certificate_validation.frontend[0].certificate_arn : (
    var.enable_test_frontend_domain ? aws_acm_certificate_validation.test_frontend[0].certificate_arn : null
  )
  api_certificate_arn = var.enable_custom_domains ? aws_acm_certificate_validation.api[0].certificate_arn : (
    var.enable_test_api_domain ? aws_acm_certificate_validation.test_api[0].certificate_arn : (
      var.enable_production_api_domain ? aws_acm_certificate_validation.api[0].certificate_arn : null
    )
  )
}

resource "aws_acm_certificate" "frontend" {
  count    = var.enable_custom_domains ? 1 : 0
  provider = aws.us_east_1

  domain_name       = local.frontend_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = local.common_tags
}

resource "aws_route53_record" "frontend_certificate_validation" {
  for_each = var.enable_custom_domains ? {
    for option in aws_acm_certificate.frontend[0].domain_validation_options : option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }
  } : {}

  zone_id = data.terraform_remote_state.shared.outputs.route53_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "frontend" {
  count    = var.enable_custom_domains ? 1 : 0
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.frontend[0].arn
  validation_record_fqdns = values(aws_route53_record.frontend_certificate_validation)[*].fqdn
}

resource "aws_acm_certificate" "api" {
  count = local.api_domain_enabled ? 1 : 0

  domain_name       = local.api_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = local.common_tags
}

resource "aws_route53_record" "api_certificate_validation" {
  for_each = local.api_domain_enabled ? {
    for option in aws_acm_certificate.api[0].domain_validation_options : option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }
  } : {}

  zone_id = data.terraform_remote_state.shared.outputs.route53_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "api" {
  count = local.api_domain_enabled ? 1 : 0

  certificate_arn         = aws_acm_certificate.api[0].arn
  validation_record_fqdns = values(aws_route53_record.api_certificate_validation)[*].fqdn
}

module "frontend" {
  source = "../../modules/frontend"

  name_prefix = local.name_prefix
  common_tags = local.common_tags
  bucket_name = "zipsai-prod-frontend-origin"
  domain_name = var.enable_custom_domains ? local.frontend_domain_name : (
    var.enable_test_frontend_domain ? var.test_frontend_domain_name : null
  )
  certificate_arn = local.frontend_certificate_arn
  api_origin_domain_name = var.enable_custom_domains ? local.api_domain_name : (
    var.enable_test_api_domain ? var.test_api_domain_name : null
  )

  depends_on = [aws_route53_record.test_api, aws_acm_certificate_validation.test_api]
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
