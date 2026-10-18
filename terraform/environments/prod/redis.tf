module "redis" {
  source               = "../../modules/redis"
  name_prefix          = local.name_prefix
  environment          = local.environment
  common_tags          = local.common_tags
  vpc_id               = data.terraform_remote_state.network.outputs.vpc_id
  subnet_id            = data.terraform_remote_state.network.outputs.private_app_subnet_2c_id
  private_dns_zone_id  = data.terraform_remote_state.network.outputs.private_dns_zone_id
  ami_id               = var.redis_ami_id
  instance_type        = var.redis_instance_type
  root_volume_size_gib = var.redis_root_volume_size_gib
  maxmemory_mib        = var.redis_maxmemory_mib
  aws_region           = var.aws_region
  client_security_group_ids = {
    api_tasks    = aws_security_group.api_tasks.id
    worker_tasks = aws_security_group.worker_tasks.id
  }
  image_version    = var.redis_image_version
  username         = var.redis_username
  password_version = var.redis_password_version
}

# ECS가 Task 시작 시 SSM 값을 주입한다. 값 변경 후에는 API/Worker 재배포가 필요하다.
# Terraform은 이름/ARN과 초기값만 관리한다. 콘솔에서 바꾼 런타임 값은 되돌리지 않는다.
locals {
  redis_client_defaults = {
    REDIS_HOST                        = module.redis.endpoint_address
    REDIS_PORT                        = tostring(module.redis.endpoint_port)
    REDIS_TLS                         = "false"
    REDIS_CONNECT_TIMEOUT             = "1s"
    REDIS_TIMEOUT                     = "1s"
    REDIS_SHUTDOWN_TIMEOUT            = "1s"
    REDIS_NOTIFICATION_PUBSUB_CHANNEL = "notification-events"
  }
}

resource "aws_ssm_parameter" "api_runtime" {
  for_each = merge(local.redis_client_defaults, { CONVERSATION_CLOSING_SCHEDULER_ENABLED = "true" })
  name     = "/zipsai/${local.environment}/backend/api/runtime/${each.key}"
  type     = "String"
  value    = each.value
  tags     = local.common_tags
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "worker_runtime" {
  for_each = merge(local.redis_client_defaults, { CONVERSATION_CLOSING_SCHEDULER_ENABLED = "false" })
  name     = "/zipsai/${local.environment}/backend/worker/runtime/${each.key}"
  type     = "String"
  value    = each.value
  tags     = local.common_tags
  lifecycle { ignore_changes = [value] }
}
