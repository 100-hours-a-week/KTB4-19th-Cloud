# CD에는 인프라 연결 정보만 전달한다. CPU/메모리, 이미지, 앱 동작 옵션은
# 이 값에 포함하지 않는다. CPU/메모리는 적용된 Service 정의, 앱 옵션은 CD 설정을 사용한다.
resource "aws_ssm_parameter" "deployment_contract" {
  name        = "/zipsai/${var.environment}/ecs/deployment-contract"
  description = "Infrastructure inputs used by Backend CD to render ECS task definitions"
  type        = "String"
  # Environment-specific Parameter ARNs make the shared CD contract exceed 4 KiB.
  tier = "Advanced"

  value = jsonencode({
    schema_version     = 1
    environment        = var.environment
    region             = data.aws_region.current.region
    cluster            = aws_ecs_cluster.this.name
    execution_role_arn = aws_iam_role.execution.arn
    common_tags        = var.common_tags
    appconfig = {
      application = var.appconfig_application_name
      environment = var.appconfig_environment_name
      profile     = var.appconfig_profile_name
    }
    loki = {
      host = var.loki_host
      port = var.loki_port
    }
    services = {
      api = {
        name          = aws_ecs_service.api.name
        family        = "${var.name_prefix}-api"
        task_role_arn = aws_iam_role.api_task.arn
        environment   = var.api_environment
        secrets       = var.api_secrets
      }
      worker = {
        name          = aws_ecs_service.worker.name
        family        = "${var.name_prefix}-worker"
        task_role_arn = aws_iam_role.worker_task.arn
        environment   = var.worker_environment
        secrets       = var.worker_secrets
      }
    }
  })

  tags = var.common_tags
}
