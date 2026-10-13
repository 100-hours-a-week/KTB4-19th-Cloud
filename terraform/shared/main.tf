locals {
  ecr_repositories = {
    backend   = "zipsai-backend"
    embedding = "zipsai-embedding"
    ai_api    = "zipsai-ai-api"
  }

  uploads_bucket_name = "zipsai-prod-uploads"
  uploads_bucket_tags = merge(var.shared_tags, {
    Environment = "prod"
  })
}

resource "aws_ecr_repository" "service" {
  for_each = local.ecr_repositories

  name                 = each.value
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.shared_tags, {
    Name = each.value
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_route53_zone" "public" {
  name    = "zipsai.co.kr"
  comment = ""

  tags = merge(var.shared_tags, {
    Name = "zipsai.co.kr"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_route53_record" "apex_a" {
  zone_id = aws_route53_zone.public.zone_id
  name    = "zipsai.co.kr"
  type    = "A"
  ttl     = 600
  records = ["52.78.171.236"]
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.public.zone_id
  name    = "www.zipsai.co.kr"
  type    = "CNAME"
  ttl     = 600
  records = ["zipsai.co.kr"]
}

resource "aws_route53_record" "mx" {
  zone_id = aws_route53_zone.public.zone_id
  name    = "zipsai.co.kr"
  type    = "MX"
  ttl     = 600
  records = [
    "10 mx1.improvmx.com",
    "20 mx2.improvmx.com",
  ]
}

resource "aws_route53_record" "spf" {
  zone_id = aws_route53_zone.public.zone_id
  name    = "zipsai.co.kr"
  type    = "TXT"
  ttl     = 600
  records = ["v=spf1 include:spf.improvmx.com ~all"]
}

resource "aws_s3_bucket" "uploads" {
  bucket        = local.uploads_bucket_name
  force_destroy = false

  tags = local.uploads_bucket_tags

  lifecycle {
    prevent_destroy = true
  }
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

resource "aws_s3_bucket_cors_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT"]
    allowed_origins = ["https://zipsai.co.kr"]
    expose_headers  = ["ETag"]
    max_age_seconds = 300
  }
}

data "aws_iam_policy_document" "uploads" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.uploads.arn, "${aws_s3_bucket.uploads.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  policy = data.aws_iam_policy_document.uploads.json

  depends_on = [aws_s3_bucket_public_access_block.uploads]
}

