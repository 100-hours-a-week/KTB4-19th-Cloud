module "appconfig" {
  source = "../../modules/appconfig"

  name_prefix = local.name_prefix
  environment = local.environment
  common_tags = local.common_tags
}

resource "aws_iam_role_policy" "legacy_appconfig" {
  name = "zipsai-prod-appconfig-read"
  role = var.legacy_ec2_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ReadDatabaseMigrationConfiguration"
      Effect = "Allow"
      Action = [
        "appconfig:StartConfigurationSession",
        "appconfig:GetLatestConfiguration",
      ]
      Resource = module.appconfig.configuration_arn
    }]
  })
}
