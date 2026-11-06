resource "aws_s3_bucket" "loki" {
  bucket        = "zipsai-v3-loki-${data.aws_caller_identity.addon_account.account_id}"
  force_destroy = false
  tags          = local.v3_tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "loki" {
  bucket                  = aws_s3_bucket.loki.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "loki" {
  bucket = aws_s3_bucket.loki.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.loki.arn, "${aws_s3_bucket.loki.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

resource "aws_iam_role" "loki" {
  name = "v3-loki-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals = {
          "aws:RequestTag/eks-cluster-arn"            = aws_eks_cluster.v3.arn
          "aws:RequestTag/kubernetes-namespace"       = "observability"
          "aws:RequestTag/kubernetes-service-account" = "loki"
        }
      }
    }]
  })
  tags = local.v3_tags
}

resource "aws_iam_role_policy" "loki" {
  name = "loki-log-storage"
  role = aws_iam_role.loki.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
      Resource = aws_s3_bucket.loki.arn
      }, {
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      Resource = "${aws_s3_bucket.loki.arn}/*"
    }]
  })
}

resource "aws_eks_pod_identity_association" "loki" {
  cluster_name    = aws_eks_cluster.v3.name
  namespace       = "observability"
  service_account = "loki"
  role_arn        = aws_iam_role.loki.arn
  tags            = local.v3_tags
  depends_on      = [aws_iam_role_policy.loki]
}

output "loki_bucket_name" {
  value = aws_s3_bucket.loki.id
}
