# V2 ALB logs only; no application payloads or existing upload buckets are moved.
data "aws_caller_identity" "alb_logs" {}

resource "aws_s3_bucket" "alb_access_logs" {
  bucket        = "${var.name_prefix}-alb-access-${data.aws_caller_identity.alb_logs.account_id}"
  force_destroy = false
  tags          = var.common_tags
}

resource "aws_s3_bucket_public_access_block" "alb_access_logs" {
  bucket                  = aws_s3_bucket.alb_access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ALB access-log delivery supports SSE-S3, not SSE-KMS.
resource "aws_s3_bucket_server_side_encryption_configuration" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Dedicated, unversioned log bucket: expiration removes objects, not just versions.
# S3 expires asynchronously after the age threshold (not exactly 14 * 24 hours).
resource "aws_s3_bucket_lifecycle_configuration" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id
  rule {
    id     = "expire-alb-logs-after-14-days"
    status = "Enabled"
    filter {
      prefix = "alb/"
    }
    expiration {
      days = 14
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_s3_bucket_policy" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAccountALBLogDelivery"
        Effect    = "Allow"
        Principal = { Service = "logdelivery.elasticloadbalancing.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.alb_access_logs.arn}/alb/AWSLogs/${data.aws_caller_identity.alb_logs.account_id}/*"
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.alb_access_logs.arn, "${aws_s3_bucket.alb_access_logs.arn}/*"]
        # AWS service calls can redact transport context; the Allow above still
        # restricts writes to ALB log delivery and this account's object prefix.
        Condition = {
          Bool = {
            "aws:SecureTransport"       = "false"
            "aws:PrincipalIsAWSService" = "false"
          }
        }
      }
    ]
  })
}
