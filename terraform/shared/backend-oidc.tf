# V2 delivery roles are separate from the existing V1 main/EC2 roles.
# The existing GitHub OIDC provider is referenced, never replaced or re-imported.
data "aws_caller_identity" "delivery" {}
data "aws_partition" "delivery" {}
data "aws_iam_openid_connect_provider" "github" {
  arn = "arn:${data.aws_partition.delivery.partition}:iam::${data.aws_caller_identity.delivery.account_id}:oidc-provider/token.actions.githubusercontent.com"
}

variable "backend_github_repository_subject" {
  description = "Verified GitHub immutable repo subject segment, including owner/repository IDs."
  type        = string
  default     = "100-hours-a-week@167328634/KTB4-19th-BE@1344653975"
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+@[0-9]+/[A-Za-z0-9_.-]+@[0-9]+$", var.backend_github_repository_subject))
    error_message = "Use the immutable owner@ID/repository@ID format verified for this repository."
  }
}

locals {
  delivery_account = data.aws_caller_identity.delivery.account_id
  delivery_prefix  = "arn:${data.aws_partition.delivery.partition}"
  backend_v2_subjects = {
    ci         = "repo:${var.backend_github_repository_subject}:ref:refs/heads/staging"
    staging_cd = "repo:${var.backend_github_repository_subject}:environment:staging"
    prod_cd    = "repo:${var.backend_github_repository_subject}:environment:production"
  }
  backend_v2_role_names = {
    ci         = "zipsai-v2-backend-ci-role"
    staging_cd = "zipsai-v2-staging-backend-cd-role"
    prod_cd    = "zipsai-v2-prod-backend-cd-role"
  }
  backend_v2_cd_environments = { staging_cd = "staging", prod_cd = "prod" }
}

resource "aws_iam_role" "backend_v2" {
  for_each = local.backend_v2_subjects
  name     = local.backend_v2_role_names[each.key]
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = { StringEquals = {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        "token.actions.githubusercontent.com:sub" = each.value
      } }
    }]
  })
  tags = merge(var.shared_tags, { Name = local.backend_v2_role_names[each.key], Purpose = "backend-v2-delivery" })
}

resource "aws_iam_role_policy" "backend_v2_ci" {
  name = "zipsai-v2-backend-image-publish"
  role = aws_iam_role.backend_v2["ci"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "EcrAuthentication", Effect = "Allow", Action = "ecr:GetAuthorizationToken", Resource = "*" },
      {
        Sid = "BackendImagesOnly", Effect = "Allow"
        Action = [
          "ecr:DescribeImages", "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload", "ecr:PutImage"
        ]
        Resource = aws_ecr_repository.service["backend"].arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "backend_v2_cd" {
  for_each = local.backend_v2_cd_environments
  name     = "zipsai-v2-${each.value}-backend-deploy"
  role     = aws_iam_role.backend_v2[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid      = "DescribeBackendImage", Effect = "Allow", Action = "ecr:DescribeImages"
        Resource = aws_ecr_repository.service["backend"].arn
      },
      {
        Sid = "ReadAppliedTaskDefinition", Effect = "Allow", Action = "ecs:DescribeTaskDefinition", Resource = "*"
      },
      {
        Sid      = "BackendTaskDefinitionTags", Effect = "Allow"
        Action   = "ecs:ListTagsForResource"
        Resource = [for service in ["api", "worker"] : "${local.delivery_prefix}:ecs:${var.aws_region}:${local.delivery_account}:task-definition/zipsai-${each.value}-${service}:*"]
      },
      {
        Sid       = "RegisterEnvironmentTaskDefinition", Effect = "Allow"
        Action    = "ecs:RegisterTaskDefinition", Resource = "*"
        Condition = { StringEquals = { "aws:RequestTag/Environment" = each.value, "aws:RequestTag/Project" = "zipsai" } }
      },
      {
        Sid       = "TagNewBackendTaskDefinition", Effect = "Allow", Action = "ecs:TagResource"
        Resource  = [for service in ["api", "worker"] : "${local.delivery_prefix}:ecs:${var.aws_region}:${local.delivery_account}:task-definition/zipsai-${each.value}-${service}:*"]
        Condition = { StringEquals = { "ecs:CreateAction" = "RegisterTaskDefinition" } }
      },
      {
        Sid      = "DescribeEnvironmentServices", Effect = "Allow", Action = "ecs:DescribeServices"
        Resource = [for service in ["api", "worker"] : "${local.delivery_prefix}:ecs:${var.aws_region}:${local.delivery_account}:service/zipsai-${each.value}-cluster/zipsai-${each.value}-${service}"]
      },
      {
        Sid       = "UpdateEnvironmentBackendServices", Effect = "Allow", Action = "ecs:UpdateService"
        Resource  = [for service in ["api", "worker"] : "${local.delivery_prefix}:ecs:${var.aws_region}:${local.delivery_account}:service/zipsai-${each.value}-cluster/zipsai-${each.value}-${service}"]
        Condition = { ArnEquals = { "ecs:cluster" = "${local.delivery_prefix}:ecs:${var.aws_region}:${local.delivery_account}:cluster/zipsai-${each.value}-cluster" } }
      },
      {
        Sid       = "PassOnlyEnvironmentTaskRoles", Effect = "Allow", Action = "iam:PassRole"
        Resource  = "${local.delivery_prefix}:iam::${local.delivery_account}:role/zipsai-${each.value}-ecs-execution-role"
        Condition = { StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" } }
      },
      {
        Sid       = "PassOnlyEnvironmentApplicationRoles", Effect = "Allow", Action = "iam:PassRole"
        Resource  = [for service in ["api", "worker"] : "${local.delivery_prefix}:iam::${local.delivery_account}:role/zipsai-${each.value}-${service}-task-role"]
        Condition = { StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" } }
      },
      {
        Sid      = "ReadStagingVerificationOnly", Effect = "Allow", Action = "ssm:GetParameter"
        Resource = [for service in ["api", "worker"] : "${local.delivery_prefix}:ssm:${var.aws_region}:${local.delivery_account}:parameter/zipsai/staging/deploy/backend/${service}/verified-images/*"]
      }
      ], each.value == "staging" ? [{
        Sid      = "WriteStagingVerificationOnly", Effect = "Allow", Action = "ssm:PutParameter"
        Resource = [for service in ["api", "worker"] : "${local.delivery_prefix}:ssm:${var.aws_region}:${local.delivery_account}:parameter/zipsai/staging/deploy/backend/${service}/verified-images/*"]
      }] : []
    )
  })
}

output "backend_v2_delivery" {
  description = "GitHub Variables and exact OIDC subjects for V2 only; existing V1 variables remain unchanged."
  value = {
    ci_repository_variable = { name = "AWS_BACKEND_CI_V2_ROLE_ARN", value = aws_iam_role.backend_v2["ci"].arn }
    cd_environment_variables = {
      staging    = { AWS_BACKEND_CD_ROLE_ARN = aws_iam_role.backend_v2["staging_cd"].arn }
      production = { AWS_BACKEND_CD_ROLE_ARN = aws_iam_role.backend_v2["prod_cd"].arn }
    }
    oidc_subjects = local.backend_v2_subjects
  }
}
