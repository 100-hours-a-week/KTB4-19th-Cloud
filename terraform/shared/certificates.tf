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

# ACM reuses the apex DNS validation token for the wildcard in both Regions.
# The existing apex CNAME is owned by prod during rollout. Move its ownership
# to shared before removing the old production certificate configuration.
resource "aws_acm_certificate_validation" "cloudfront" {
  provider        = aws.us_east_1
  certificate_arn = aws_acm_certificate.cloudfront.arn
}

resource "aws_acm_certificate_validation" "api_alb" {
  certificate_arn = aws_acm_certificate.api_alb.arn
}

output "cloudfront_certificate_arn" {
  description = "Validated public certificate in us-east-1 for CloudFront."
  value       = aws_acm_certificate_validation.cloudfront.certificate_arn
}

output "api_alb_certificate_arn" {
  description = "Validated wildcard certificate in the shared AWS Region for API ALBs."
  value       = aws_acm_certificate_validation.api_alb.certificate_arn
}
