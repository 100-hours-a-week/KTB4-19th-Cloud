locals {
  frontend_domain_name = "v2.zipsai.co.kr"
  api_domain_name      = "api-v2.zipsai.co.kr"

  frontend_certificate_arn = var.enable_custom_domains ? data.terraform_remote_state.shared.outputs.cloudfront_certificate_arn : null
  api_certificate_arn      = var.enable_custom_domains ? data.terraform_remote_state.shared.outputs.api_alb_certificate_arn : null
}

module "frontend" {
  source = "../../modules/frontend"

  name_prefix            = local.name_prefix
  common_tags            = local.common_tags
  bucket_name            = "zipsai-staging-frontend-origin"
  domain_name            = var.enable_custom_domains ? local.frontend_domain_name : null
  certificate_arn        = local.frontend_certificate_arn
  api_origin_domain_name = var.enable_custom_domains ? local.api_domain_name : null

  # The HTTPS origin DNS must exist before CloudFront attempts API requests.
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
  count = var.enable_custom_domains ? 1 : 0

  zone_id = data.terraform_remote_state.shared.outputs.route53_zone_id
  name    = local.api_domain_name
  type    = "A"

  alias {
    name                   = module.ecs.alb_dns_name
    zone_id                = module.ecs.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_s3_bucket" "uploads" {
  bucket        = var.uploads_bucket_name
  force_destroy = false

  tags = merge(local.common_tags, {
    Name = var.uploads_bucket_name
  })
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_cors_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT"]
    allowed_origins = ["https://${local.frontend_domain_name}"]
    expose_headers  = ["ETag"]
    max_age_seconds = 300
  }
}
