data "aws_security_group" "rehearsal_source" {
  count = var.enable_rehearsal_source ? 1 : 0

  id = var.rehearsal_source_security_group_id
}

data "aws_iam_role" "rehearsal_source" {
  count = var.enable_rehearsal_source ? 1 : 0

  name = var.rehearsal_source_ec2_role_name
}

data "aws_security_group" "ssm_endpoints" {
  count = var.enable_rehearsal_source ? 1 : 0

  vpc_id = data.terraform_remote_state.network.outputs.vpc_id

  filter {
    name   = "group-name"
    values = ["zipsai-shared-ssm-endpoints-sg"]
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssm_from_rehearsal_source" {
  count = var.enable_rehearsal_source ? 1 : 0

  security_group_id            = data.aws_security_group.ssm_endpoints[0].id
  description                  = "HTTPS from the temporary Staging rehearsal source"
  referenced_security_group_id = data.aws_security_group.rehearsal_source[0].id
  from_port                    = 443
  ip_protocol                  = "tcp"
  to_port                      = 443

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ssm-from-rehearsal-source"
  })
}

resource "aws_vpc_security_group_ingress_rule" "rehearsal_source_node_exporter" {
  count = var.enable_rehearsal_source ? 1 : 0

  security_group_id            = data.aws_security_group.rehearsal_source[0].id
  description                  = "Node Exporter scrape from the private monitoring server"
  referenced_security_group_id = data.terraform_remote_state.network.outputs.monitoring_server_security_group_id
  from_port                    = 9100
  ip_protocol                  = "tcp"
  to_port                      = 9100

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rehearsal-source-node-exporter"
  })
}

resource "aws_vpc_security_group_ingress_rule" "rehearsal_source_mysql_exporter" {
  count = var.enable_rehearsal_source ? 1 : 0

  security_group_id            = data.aws_security_group.rehearsal_source[0].id
  description                  = "MySQL Exporter scrape from the private monitoring server"
  referenced_security_group_id = data.terraform_remote_state.network.outputs.monitoring_server_security_group_id
  from_port                    = 9104
  ip_protocol                  = "tcp"
  to_port                      = 9104

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rehearsal-source-mysql-exporter"
  })
}

resource "aws_vpc_security_group_ingress_rule" "rehearsal_source_application_metrics" {
  count = var.enable_rehearsal_source ? 1 : 0

  security_group_id            = data.aws_security_group.rehearsal_source[0].id
  description                  = "Backend and migration Worker metrics from the private monitoring server"
  referenced_security_group_id = data.terraform_remote_state.network.outputs.monitoring_server_security_group_id
  from_port                    = 8080
  ip_protocol                  = "tcp"
  to_port                      = 8081

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rehearsal-source-application-metrics"
  })
}

resource "aws_vpc_security_group_egress_rule" "mysql_to_rehearsal_source" {
  count = var.enable_rehearsal_source ? 1 : 0

  security_group_id            = module.mysql.security_group_id
  description                  = "MySQL replication pull from the temporary rehearsal source"
  referenced_security_group_id = data.aws_security_group.rehearsal_source[0].id
  from_port                    = 3306
  ip_protocol                  = "tcp"
  to_port                      = 3306

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mysql-to-rehearsal-source"
  })
}

resource "aws_vpc_security_group_ingress_rule" "rehearsal_source_from_mysql" {
  count = var.enable_rehearsal_source ? 1 : 0

  security_group_id            = data.aws_security_group.rehearsal_source[0].id
  description                  = "MySQL replication from the Staging database nodes"
  referenced_security_group_id = module.mysql.security_group_id
  from_port                    = 3306
  ip_protocol                  = "tcp"
  to_port                      = 3306

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rehearsal-source-from-mysql"
  })
}

resource "aws_iam_role_policy" "rehearsal_source_appconfig" {
  count = var.enable_rehearsal_source ? 1 : 0

  name = "${local.name_prefix}-rehearsal-appconfig-read"
  role = data.aws_iam_role.rehearsal_source[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ReadStagingDatabaseMigrationConfiguration"
      Effect = "Allow"
      Action = [
        "appconfig:StartConfigurationSession",
        "appconfig:GetLatestConfiguration",
      ]
      Resource = module.appconfig.configuration_arn
    }]
  })
}

resource "aws_iam_role_policy" "rehearsal_source_parameters" {
  count = var.enable_rehearsal_source ? 1 : 0

  name = "${local.name_prefix}-rehearsal-parameters-read"
  role = data.aws_iam_role.rehearsal_source[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ReadStagingV2DatabasePassword"
      Effect = "Allow"
      Action = [
        "ssm:GetParameter",
        "ssm:GetParameters",
      ]
      Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/zipsai/staging/mysql/password"
    }]
  })
}

resource "aws_route53_record" "rehearsal_source" {
  count = var.enable_rehearsal_source ? 1 : 0

  zone_id = data.terraform_remote_state.network.outputs.private_dns_zone_id
  name    = "mysql-source.staging.zipsai.internal"
  type    = "A"
  ttl     = 30
  records = [var.rehearsal_source_private_ip]
}
