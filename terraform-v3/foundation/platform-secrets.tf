# Each store assumes an environment reader to enforce Parameter Store path isolation.
resource "aws_iam_role" "parameter_reader" {
  for_each = toset(["staging", "prod", "observability"])
  name     = "v3-${each.key}-parameter-reader"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = aws_iam_role.addon["eso"].arn }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
  tags = local.v3_tags
}

resource "aws_iam_role_policy" "parameter_reader" {
  for_each = aws_iam_role.parameter_reader
  name     = "environment-parameter-read"
  role     = each.value.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
      Resource = "arn:aws:ssm:ap-northeast-2:${data.aws_caller_identity.addon_account.account_id}:parameter/zipsai/v3/${each.key}/*"
    }]
  })
}

data "aws_acm_certificate" "shared_api" {
  domain      = "*.zipsai.co.kr"
  statuses    = ["ISSUED"]
  most_recent = true
}

output "platform_connection_values" {
  description = "Non-secret Argo CD root Helm overrides from existing AWS resources."
  value = {
    albController = {
      vpcId = data.aws_vpc.shared.id
    }
    secretStores = {
      accountId = data.aws_caller_identity.addon_account.account_id
    }
    platform = {
      ingress = {
        certificateArn = data.aws_acm_certificate.shared_api.arn
        publicSubnetIds = [
          data.aws_subnet.shared["public_2a"].id,
          data.aws_subnet.shared["public_2c"].id,
        ]
      }
    }
  }
}
