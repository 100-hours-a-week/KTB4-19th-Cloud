resource "aws_s3_bucket" "frontend" {
  bucket        = var.bucket_name
  force_destroy = false

  tags = merge(var.common_tags, {
    Name = var.bucket_name
  })
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.name_prefix}-frontend-oac"
  description                       = "Private S3 origin access for ${var.name_prefix}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_cloudfront_cache_policy" "api_disabled" {
  count = var.api_origin_domain_name == null ? 0 : 1
  name  = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "api_forward" {
  count = var.api_origin_domain_name == null ? 0 : 1
  name  = "Managed-AllViewerExceptHostHeader"
}

resource "aws_cloudfront_function" "spa" {
  count   = var.api_origin_domain_name == null ? 0 : 1
  name    = "${var.name_prefix}-frontend-spa"
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite SPA navigation only; never replace API errors with index.html"
  publish = true
  code = var.canonical_domain_name == null ? file("${path.module}/functions/spa.js") : templatefile(
    "${path.module}/functions/spa-canonical.js.tftpl", { canonical_domain_name = var.canonical_domain_name }
  )
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.name_prefix} Frontend"
  default_root_object = "index.html"
  price_class         = var.price_class
  aliases             = var.domain_name == null ? [] : distinct(concat([var.domain_name], var.additional_domain_names))

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "${var.name_prefix}-frontend-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  dynamic "origin" {
    for_each = var.api_origin_domain_name == null ? [] : [var.api_origin_domain_name]
    content {
      domain_name = origin.value
      origin_id   = "${var.name_prefix}-api-alb"
      custom_origin_config {
        http_port                = 80
        https_port               = 443
        origin_protocol_policy   = "https-only"
        origin_ssl_protocols     = ["TLSv1.2"]
        origin_read_timeout      = 60
        origin_keepalive_timeout = 5
      }
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "${var.name_prefix}-frontend-s3"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"

    dynamic "function_association" {
      for_each = var.api_origin_domain_name == null ? [] : [1]
      content {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.spa[0].arn
      }
    }
  }

  dynamic "ordered_cache_behavior" {
    # Exact /api is protected from the SPA fallback as well as /api/*.
    for_each = var.api_origin_domain_name == null ? [] : ["/api", "/api/*"]
    content {
      path_pattern             = ordered_cache_behavior.value
      allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods           = ["GET", "HEAD"]
      target_origin_id         = "${var.name_prefix}-api-alb"
      viewer_protocol_policy   = "https-only"
      compress                 = false
      cache_policy_id          = data.aws_cloudfront_cache_policy.api_disabled[0].id
      origin_request_policy_id = data.aws_cloudfront_origin_request_policy.api_forward[0].id
    }
  }

  dynamic "custom_error_response" {
    # Preserve the old SPA mapping only for S3-only users. API responses keep their status/body.
    # TTL zero also disables CloudFront's separate error cache, not just normal response caching.
    for_each = var.api_origin_domain_name == null ? [403, 404] : [400, 403, 404, 405, 414, 416, 500, 501, 502, 503, 504]
    content {
      error_code            = custom_error_response.value
      response_code         = var.api_origin_domain_name == null ? 200 : null
      response_page_path    = var.api_origin_domain_name == null ? "/index.html" : null
      error_caching_min_ttl = 0
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn            = var.certificate_arn
    cloudfront_default_certificate = var.certificate_arn == null
    minimum_protocol_version       = var.certificate_arn == null ? "TLSv1" : "TLSv1.2_2021"
    ssl_support_method             = var.certificate_arn == null ? null : "sni-only"
  }

  tags = var.common_tags
}

data "aws_iam_policy_document" "frontend" {
  statement {
    sid     = "AllowCloudFrontRead"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.frontend.arn}/*",
    ]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.frontend.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend.json

  depends_on = [aws_s3_bucket_public_access_block.frontend]
}
