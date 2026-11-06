locals {
  certificate_domain = aws_route53_zone.public.name
  wildcard_domain    = "*.${local.certificate_domain}"
}

resource "aws_acm_certificate" "cloudfront" {
  provider = aws.us_east_1

  domain_name               = local.certificate_domain
  subject_alternative_names = [local.wildcard_domain]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate" "api_alb" {
  domain_name       = local.wildcard_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Apex and wildcard certificates use the same DNS validation CNAME, including
# across Regions. Manage it once so old per-domain certificates can be removed.
locals {
  certificate_validation = one([
    for option in aws_acm_certificate.cloudfront.domain_validation_options : option
    if option.domain_name == local.certificate_domain
  ])
}

resource "aws_route53_record" "certificate_validation" {
  zone_id = aws_route53_zone.public.zone_id
  name    = local.certificate_validation.resource_record_name
  type    = local.certificate_validation.resource_record_type
  ttl     = 60
  records = [local.certificate_validation.resource_record_value]

  lifecycle {
    prevent_destroy = true
  }
}

# Issue #24: prod must release ownership with destroy=false before this import.
# Derive the import ID from the live certificate and public zone, not a copied token.
import {
  to = aws_route53_record.certificate_validation
  id = "${aws_route53_zone.public.zone_id}_${trimsuffix(local.certificate_validation.resource_record_name, ".")}_${local.certificate_validation.resource_record_type}"
}

resource "aws_acm_certificate_validation" "cloudfront" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cloudfront.arn
  validation_record_fqdns = [aws_route53_record.certificate_validation.fqdn]
}

resource "aws_acm_certificate_validation" "api_alb" {
  certificate_arn         = aws_acm_certificate.api_alb.arn
  validation_record_fqdns = [aws_route53_record.certificate_validation.fqdn]
}

output "cloudfront_certificate_arn" {
  description = "Validated public certificate in us-east-1 for CloudFront."
  value       = aws_acm_certificate_validation.cloudfront.certificate_arn
}

output "api_alb_certificate_arn" {
  description = "Validated wildcard certificate in the shared AWS Region for API ALBs."
  value       = aws_acm_certificate_validation.api_alb.certificate_arn
}
