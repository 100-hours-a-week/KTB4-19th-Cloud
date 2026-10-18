# AI V2 roles: existing V1 roles/provider are not changed.
variable "ai_github_repository_subject" {
  description = "Immutable GitHub owner@ID/repository@ID subject verified via GitHub API."
  type        = string
  default     = "100-hours-a-week@167328634/KTB4-19th-AI@1344655176"
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+@[0-9]+/[A-Za-z0-9_.-]+@[0-9]+$", var.ai_github_repository_subject))
    error_message = "Use the verified immutable GitHub subject."
  }
}

locals {
  ai_v2_subjects = {
    ci         = format("repo:%s:ref:refs/heads/staging", var.ai_github_repository_subject)
    staging_cd = format("repo:%s:environment:staging", var.ai_github_repository_subject)
    prod_cd    = format("repo:%s:environment:production", var.ai_github_repository_subject)
  }
  ai_v2_role_names = {
    ci         = "zipsai-v2-ai-ci-role"
    staging_cd = "zipsai-v2-staging-ai-cd-role"
    prod_cd    = "zipsai-v2-prod-ai-cd-role"
  }
  ai_v2_environments = { staging_cd = "staging", prod_cd = "prod" }
  ai_v2_ecr_arns     = [for key in ["ai_api", "embedding"] : aws_ecr_repository.service[key].arn]
}

resource "aws_iam_role" "ai_v2" {
  for_each = local.ai_v2_subjects
  name     = local.ai_v2_role_names[each.key]
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Condition = { StringEquals = {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        "token.actions.githubusercontent.com:sub" = each.value
      } }
    }]
  })
  tags = merge(var.shared_tags, { Name = local.ai_v2_role_names[each.key], Purpose = "ai-v2-delivery" })
}

resource "aws_iam_role_policy" "ai_v2_ci" {
  role = aws_iam_role.ai_v2["ci"].id
  name = "zipsai-v2-ai-image-publish"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = "ecr:GetAuthorizationToken", Resource = "*" },
      {
        Effect = "Allow", Resource = local.ai_v2_ecr_arns
        Action = ["ecr:DescribeImages", "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload", "ecr:PutImage"]
      }
    ]
  })
}

resource "aws_iam_role_policy" "ai_v2_cd" {
  for_each = local.ai_v2_environments
  role     = aws_iam_role.ai_v2[each.key].id
  name     = format("zipsai-v2-%s-ai-deploy", each.value)
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      { Effect = "Allow", Action = "ecr:DescribeImages", Resource = local.ai_v2_ecr_arns },
      {
        Effect = "Allow", Action = "ssm:GetParameter"
        Resource = [
          format("%s:ssm:%s:%s:parameter/zipsai/%s/ai/deployment-contract", local.delivery_prefix, var.aws_region, local.delivery_account, each.value),
          format("%s:ssm:%s:%s:parameter/zipsai/staging/deploy/ai-v2/*/verified/*", local.delivery_prefix, var.aws_region, local.delivery_account)
        ]
      },
      {
        Effect = "Allow", Action = ["ec2:DescribeInstances", "ssm:GetCommandInvocation"], Resource = "*"
      },
      {
        Effect   = "Allow", Action = "ssm:SendCommand"
        Resource = format("%s:ssm:%s::document/AWS-RunShellScript", local.delivery_prefix, var.aws_region)
      },
      {
        Effect   = "Allow", Action = "ssm:SendCommand"
        Resource = format("%s:ec2:%s:%s:instance/*", local.delivery_prefix, var.aws_region, local.delivery_account)
        Condition = { StringEquals = {
          "ssm:resourceTag/Project"     = "zipsai"
          "ssm:resourceTag/Environment" = each.value
          "ssm:resourceTag/Name"        = [for service in ["ai-api", "embedding", "qdrant"] : format("zipsai-%s-%s", each.value, service)]
        } }
      }
      ], each.value == "staging" ? [{
        Effect   = "Allow", Action = "ssm:PutParameter"
        Resource = format("%s:ssm:%s:%s:parameter/zipsai/staging/deploy/ai-v2/*/verified/*", local.delivery_prefix, var.aws_region, local.delivery_account)
    }] : [])
  })
}

output "ai_v2_delivery_roles" {
  value = { for key, role in aws_iam_role.ai_v2 : key => role.arn }
}
