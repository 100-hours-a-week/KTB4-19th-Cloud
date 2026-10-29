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
  ami_id               = var.ami_id
  data_volume_size_gib = var.data_volume_size_gib

  grafana_admin_password_parameter_name = var.grafana_admin_password_parameter_name

}
