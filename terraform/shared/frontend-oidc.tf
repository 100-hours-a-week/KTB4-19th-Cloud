# V2 frontend delivery only. Preserve the existing V1 role and GitHub provider.
variable "frontend_github_repository_subject" {
  description = "Verified immutable GitHub owner/repository subject used by the FE repository."
  type        = string
  default     = "100-hours-a-week@167328634/KTB4-19th-FE@1344654586"
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+@[0-9]+/[A-Za-z0-9_.-]+@[0-9]+$", var.frontend_github_repository_subject))
    error_message = "Use the verified immutable GitHub subject with owner and repository IDs."
  }
}

variable "frontend_v2_delivery_targets" {
  description = "Existing V2 frontend buckets and distributions; never point these at V1."
  type = map(object({
    bucket_name     = string
    distribution_id = string
  }))
  default = {
    staging = {
      bucket_name     = "zipsai-staging-frontend-origin"
      distribution_id = "ENXWBDFQNIXMV"
    }
    production = {
      bucket_name     = "zipsai-prod-frontend-origin"
      distribution_id = "E2H4XO5YU2FGHZ"
    }
  }
  validation {
    condition = (
      toset(keys(var.frontend_v2_delivery_targets)) == toset(["staging", "production"]) &&
      var.frontend_v2_delivery_targets["staging"].bucket_name == "zipsai-staging-frontend-origin" &&
      var.frontend_v2_delivery_targets["production"].bucket_name == "zipsai-prod-frontend-origin"
    )
    error_message = "Only the existing isolated V2 staging/production frontend buckets are allowed."
  }
}

data "aws_cloudfront_distribution" "frontend_v2_delivery" {
  for_each = var.frontend_v2_delivery_targets
  id       = each.value.distribution_id
}

resource "aws_iam_role" "frontend_v2_cd" {
  for_each = var.frontend_v2_delivery_targets
  name     = "zipsai-v2-${each.key == "production" ? "prod" : each.key}-frontend-cd-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Condition = { StringEquals = {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        "token.actions.githubusercontent.com:sub" = "repo:${var.frontend_github_repository_subject}:environment:${each.key}"
      } }
    }]
  })
  tags = merge(var.shared_tags, { Purpose = "frontend-v2-delivery", DeploymentEnvironment = each.key })

}

resource "aws_iam_role_policy" "frontend_v2_cd" {
  for_each = var.frontend_v2_delivery_targets
  name     = "frontend-static-artifact-delivery"
  role     = aws_iam_role.frontend_v2_cd[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListOwnFrontendBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "${local.delivery_prefix}:s3:::${each.value.bucket_name}"
      },
      {
        Sid      = "PublishAndReadOwnStaticFiles"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${local.delivery_prefix}:s3:::${each.value.bucket_name}/*"
      },
      {
        Sid      = "InvalidateOwnFrontendDistribution"
        Effect   = "Allow"
        Action   = ["cloudfront:GetDistribution", "cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
        Resource = data.aws_cloudfront_distribution.frontend_v2_delivery[each.key].arn
      },
      {
        Sid      = "StagingVerificationHistory"
        Effect   = "Allow"
        Action   = each.key == "staging" ? "ssm:PutParameter" : "ssm:GetParameter"
        Resource = "${local.delivery_prefix}:ssm:${var.aws_region}:${local.delivery_account}:parameter/zipsai/staging/deploy/frontend/verified-runs/*"
      }
    ]
  })
}

output "frontend_v2_github_environment_variables" {
  value = { for environment, target in var.frontend_v2_delivery_targets : environment => {
    AWS_FRONTEND_CD_V2_ROLE_ARN = aws_iam_role.frontend_v2_cd[environment].arn
    FRONTEND_DISTRIBUTION_ID    = target.distribution_id
  } }
}
