locals {
  environment = "prod"
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
  description = "Security group for Production ECS API tasks"
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
  description = "Security group for Production ECS Worker tasks"
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

module "document_jobs" {
  source = "../../modules/sqs"

  name_prefix = local.name_prefix
  common_tags = local.common_tags
}
