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

resource "aws_iam_role_policy" "legacy_migration_parameters" {
  name = "zipsai-prod-migration-parameters-read"
  role = var.legacy_ec2_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ReadDatabaseMigrationParameters"
      Effect = "Allow"
      Action = ["ssm:GetParameter"]
      Resource = [
        "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/zipsai/prod/mysql-v2/password",
        "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/zipsai/prod/mysql-v1/exporter-password",
      ]
    }]
  })
}
