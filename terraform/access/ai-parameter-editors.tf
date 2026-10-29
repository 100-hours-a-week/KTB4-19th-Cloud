data "aws_kms_alias" "parameter_store" {
  name = "alias/aws/ssm"
}

# User-approved account-wide parameter access in Seoul, including non-AI secrets.
# Reuse the AI-only group; do not attach this to the all-team log-viewers group.
resource "aws_iam_policy" "ai_parameter_editors" {
  name        = "Zipsai-AIParameterStoreEditors"
  description = "AI team reads and edits all Seoul Parameter Store values including SecureString; no deletion"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "BrowseParameterMetadata"
        Effect    = "Allow"
        Action    = ["ssm:DescribeParameters"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = local.region } }
      },
      {
        Sid    = "ReadAndWriteParameterValues"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath",
          "ssm:GetParameterHistory", "ssm:ListTagsForResource", "ssm:PutParameter"
        ]
        Resource = "${local.prefix}:ssm:${local.region}:${local.account}:parameter/*"
      },
      {
        Sid      = "SecureStringThroughParameterStoreOnly"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
        Resource = data.aws_kms_alias.parameter_store.target_key_arn
        Condition = {
          StringEquals = { "kms:ViaService" = "ssm.${local.region}.amazonaws.com" }
          StringLike = {
            "kms:EncryptionContext:PARAMETER_ARN" = "${local.prefix}:ssm:${local.region}:${local.account}:parameter/*"
          }
        }
      }
    ]
  })
  tags = { Project = "zipsai", ManagedBy = "Terraform", Component = "ai-parameter-access" }
}

resource "aws_iam_group_policy_attachment" "ai_parameter_editors" {
  group      = data.aws_iam_group.qdrant_readers.group_name
  policy_arn = aws_iam_policy.ai_parameter_editors.arn
}
