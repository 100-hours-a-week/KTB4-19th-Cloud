locals {
  environment = "staging"
  name_prefix = "zipsai-${local.environment}"

  common_tags = {
    Project     = "zipsai"
    Environment = local.environment
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

resource "aws_security_group" "api_tasks" {
  name        = "${local.name_prefix}-api-tasks-sg"
  description = "Security group for Staging ECS API tasks"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  revoke_rules_on_delete = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-api-tasks-sg"
  })
}

resource "aws_vpc_security_group_egress_rule" "api_tasks_all_ipv4" {
  security_group_id = aws_security_group.api_tasks.id
  description       = "Application dependencies through the private subnet route"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-api-tasks-all-egress"
  })
}

resource "aws_security_group" "worker_tasks" {
  name        = "${local.name_prefix}-worker-tasks-sg"
  description = "Security group for Staging ECS Worker tasks"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  revoke_rules_on_delete = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-worker-tasks-sg"
  })
}

resource "aws_vpc_security_group_egress_rule" "worker_tasks_all_ipv4" {
  security_group_id = aws_security_group.worker_tasks.id
  description       = "Worker dependencies through the private subnet route"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-worker-tasks-all-egress"
  })
}

module "mysql" {
  source = "../../modules/mysql"

  name_prefix    = local.name_prefix
  common_tags    = local.common_tags
  vpc_id         = data.terraform_remote_state.network.outputs.vpc_id
  vpc_cidr_block = data.terraform_remote_state.network.outputs.vpc_cidr_block

  ami_id        = var.mysql_ami_id
  instance_type = var.mysql_instance_type

  primary_subnet_id         = data.terraform_remote_state.network.outputs.private_data_subnet_ids.ap_northeast_2c
  primary_availability_zone = "ap-northeast-2c"
  replica_subnet_id         = data.terraform_remote_state.network.outputs.private_data_subnet_ids.ap_northeast_2a
  replica_availability_zone = "ap-northeast-2a"

  client_security_group_ids = {
    api_tasks    = aws_security_group.api_tasks.id
    worker_tasks = aws_security_group.worker_tasks.id
  }
  monitoring_security_group_id = data.terraform_remote_state.network.outputs.monitoring_server_security_group_id
  data_volume_size_gib         = var.mysql_data_volume_size_gib
  secret_parameter_arns = [
    "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/zipsai/staging/mysql/password",
    "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/zipsai/staging/mysql/root-password",
    "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/zipsai/staging/mysql/replication-password",
    "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/zipsai/staging/mysql/exporter-password",
  ]
}
