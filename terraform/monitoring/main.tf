locals {
  name_prefix = "zipsai-monitoring"

  common_tags = {
    Project     = "zipsai"
    Environment = "shared"
    Component   = "monitoring"
    ManagedBy   = "Terraform"
  }
}

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "zipsai-v2-terraform-state"
    key    = "network/terraform.tfstate"
    region = var.aws_region
  }
}

module "monitoring" {
  source = "../modules/monitoring"

  name_prefix = local.name_prefix
  common_tags = local.common_tags
  aws_region  = var.aws_region

  subnet_id            = data.terraform_remote_state.network.outputs.private_app_subnet_2c_id
  security_group_id    = data.terraform_remote_state.network.outputs.monitoring_server_security_group_id
  private_dns_zone_id  = data.terraform_remote_state.network.outputs.private_dns_zone_id
  instance_type        = var.instance_type
  data_volume_size_gib = var.data_volume_size_gib

  grafana_admin_password_parameter_name = var.grafana_admin_password_parameter_name

  compose_config_gzip_base64      = base64gzip(file("${path.root}/../../monitoring/docker-compose.yml"))
  prometheus_config_gzip_base64   = base64gzip(file("${path.root}/../../monitoring/prometheus.yml"))
  loki_config_gzip_base64         = base64gzip(file("${path.root}/../../monitoring/loki.yml"))
  grafana_datasources_gzip_base64 = base64gzip(file("${path.root}/../../monitoring/grafana-datasources.yml"))
}

resource "aws_route53_record" "legacy_mysql" {
  zone_id = data.terraform_remote_state.network.outputs.private_dns_zone_id
  name    = "mysql-v1.prod.zipsai.internal"
  type    = "A"
  ttl     = 30
  records = [var.legacy_mysql_private_ip]
}
