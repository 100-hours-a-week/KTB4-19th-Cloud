data "terraform_remote_state" "shared" {
  backend = "s3"

  config = {
    bucket = "zipsai-v2-terraform-state"
    key    = "shared/terraform.tfstate"
    region = var.aws_region
  }
}

data "aws_caller_identity" "current" {}

locals {
  backend_image_uri = "${data.terraform_remote_state.shared.outputs.ecr_repository_urls.backend}:${var.backend_image_tag}"
  mysql_jdbc_url    = "jdbc:mysql://${module.mysql.private_ips.primary}:3306/zipsai?serverTimezone=Asia/Seoul&characterEncoding=UTF-8&allowPublicKeyRetrieval=true&useSSL=false"

  backend_environment = {
    DB_URL             = local.mysql_jdbc_url
    DB_USERNAME        = "zipsai_app"
    AI_API_URL         = var.ai_api_url != null ? var.ai_api_url : module.ai.api_url
    AWS_REGION         = var.aws_region
    S3_UPLOAD_BUCKET   = var.uploads_bucket_name
    SENTRY_ENVIRONMENT = "staging"
  }

  backend_secrets = {
    DB_PASSWORD = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/zipsai/staging/mysql/password"
    JWT_SECRET  = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/zipsai/staging/jwt/secret"
  }
}

module "ecs" {
  source = "../../modules/ecs"

  name_prefix = local.name_prefix
  environment = local.environment
  common_tags = local.common_tags
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  public_subnet_ids = [
    data.terraform_remote_state.network.outputs.public_subnet_2a_id,
    data.terraform_remote_state.network.outputs.public_subnet_2c_id,
  ]
  private_app_subnet_ids = [data.terraform_remote_state.network.outputs.private_app_subnet_2c_id]

  api_security_group_id               = aws_security_group.api_tasks.id
  worker_security_group_id            = aws_security_group.worker_tasks.id
  monitoring_client_security_group_id = data.terraform_remote_state.network.outputs.monitoring_client_security_group_id
  backend_image_uri                   = local.backend_image_uri

  appconfig_application_name  = module.appconfig.application_name
  appconfig_environment_name  = module.appconfig.environment_name
  appconfig_profile_name      = module.appconfig.configuration_profile_name
  appconfig_configuration_arn = module.appconfig.configuration_arn

  api_environment    = local.backend_environment
  worker_environment = local.backend_environment
  api_secrets = merge(local.backend_secrets, {
    REDIS_USERNAME = module.redis.username_parameter_arn
    REDIS_PASSWORD = module.redis.password_parameter_arn
  }, { for name, parameter in aws_ssm_parameter.api_runtime : name => parameter.arn })
  worker_secrets = merge(local.backend_secrets, {
    REDIS_USERNAME = module.redis.username_parameter_arn
    REDIS_PASSWORD = module.redis.password_parameter_arn
  }, { for name, parameter in aws_ssm_parameter.worker_runtime : name => parameter.arn })
  worker_command = var.worker_command

  api_desired_count    = var.api_desired_count
  worker_desired_count = var.worker_desired_count

  uploads_bucket_name = var.uploads_bucket_name
  certificate_arn     = local.api_certificate_arn
  enable_https        = var.enable_custom_domains
  health_check_path   = "/api/actuator/health/readiness"
  liveness_check_path = "/api/actuator/health/liveness"
  # Allow JVM startup and ALB recovery without changing production defaults.
  api_health_check_grace_period_seconds = 120
  api_health_check_interval_seconds     = 10
}
