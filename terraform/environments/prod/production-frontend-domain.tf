variable "enable_production_frontend_domain" {
  description = "Prepare production frontend TLS/CloudFront aliases without changing the apex DNS owned by shared State."
  type        = bool
  default     = false
}

resource "aws_acm_certificate" "production_frontend" {
  count    = var.enable_production_frontend_domain ? 1 : 0
  provider = aws.us_east_1

  domain_name = local.frontend_domain_name
  subject_alternative_names = concat(
    ["www.zipsai.co.kr"],
    var.enable_test_frontend_domain ? [var.test_frontend_domain_name] : []
  )
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
  tags = local.common_tags
}

resource "aws_route53_record" "production_frontend_certificate_validation" {
  for_each = var.enable_production_frontend_domain ? {
    for option in aws_acm_certificate.production_frontend[0].domain_validation_options : option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }
    # The same-account ACM validation token is already managed by test_frontend.
    if !(var.enable_test_frontend_domain && option.domain_name == var.test_frontend_domain_name)
  } : {}

  zone_id = data.terraform_remote_state.shared.outputs.route53_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "production_frontend" {
  count    = var.enable_production_frontend_domain ? 1 : 0
  provider = aws.us_east_1

  certificate_arn = aws_acm_certificate.production_frontend[0].arn
  validation_record_fqdns = concat(
    values(aws_route53_record.production_frontend_certificate_validation)[*].fqdn,
    var.enable_test_frontend_domain ? values(aws_route53_record.test_frontend_certificate_validation)[*].fqdn : []
  )
}

# Stage 1: apply prod with enable_production_frontend_domain=true, then verify
# CloudFront is Deployed, TLS and app behavior. Keep this flag true thereafter.
# Stage 2: only after approval, change shared.production_frontend_alias_target.
# Never enable legacy enable_custom_domains for this cutover: shared already
# manages the apex A record; a second State must not create the same record.
