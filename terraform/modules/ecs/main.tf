locals {
  https_enabled         = var.enable_https != null ? var.enable_https : var.certificate_arn != null
  api_container_name    = "api"
  worker_container_name = "worker"
  log_router_name       = "log-router"
  appconfig_agent_name  = "appconfig-agent"
  all_secret_arns       = toset(concat(values(var.api_secrets), values(var.worker_secrets)))

  appconfig_client_environment = {
    APPCONFIG_ENDPOINT    = "http://localhost:2772"
    APPCONFIG_APPLICATION = var.appconfig_application_name
    APPCONFIG_ENVIRONMENT = var.appconfig_environment_name
    APPCONFIG_PROFILE     = var.appconfig_profile_name
  }

  log_router_container = {
    name              = local.log_router_name
    image             = var.firelens_image_uri
    essential         = true
    memoryReservation = 64
    environment       = []
    mountPoints       = []
    portMappings      = []
    systemControls    = []
    user              = "0"
    volumesFrom       = []

    firelensConfiguration = {
      type = "fluentbit"
      options = {
        enable-ecs-log-metadata = "true"
      }
    }
  }

  appconfig_agent_container = {
    name              = local.appconfig_agent_name
    image             = var.appconfig_agent_image_uri
    essential         = true
    memoryReservation = 64
    mountPoints       = []
    systemControls    = []
    volumesFrom       = []

    portMappings = [{
      name          = "appconfig"
      containerPort = 2772
      hostPort      = 2772
      protocol      = "tcp"
    }]

    environment = [
      {
        name  = "SERVICE_REGION"
        value = data.aws_region.current.region
      },
      {
        name  = "POLL_INTERVAL"
        value = var.appconfig_poll_interval
      },
      {
        name  = "PREFETCH_LIST"
        value = "${var.appconfig_application_name}:${var.appconfig_environment_name}:${var.appconfig_profile_name}"
      },
      {
        name  = "LOG_LEVEL"
        value = "info"
      },
    ]

    dependsOn = [{
      containerName = local.log_router_name
      condition     = "START"
    }]

    logConfiguration = {
      logDriver = "awsfirelens"
      options = {
        Name        = "loki"
        Host        = var.loki_host
        Port        = tostring(var.loki_port)
        labels      = "environment=${var.environment},service=appconfig-agent"
        line_format = "json"
      }
    }
  }

  api_container = {
    name           = local.api_container_name
    image          = var.backend_image_uri
    essential      = true
    mountPoints    = []
    systemControls = []
    volumesFrom    = []

    portMappings = [{
      name          = "http"
      containerPort = 8080
      hostPort      = 8080
      protocol      = "tcp"
      appProtocol   = "http"
    }]

    environment = [for name, value in merge(var.api_environment, local.appconfig_client_environment) : {
      name  = name
      value = value
    }]

    secrets = [for name, value_from in var.api_secrets : {
      name      = name
      valueFrom = value_from
    }]

    healthCheck = {
      command     = ["CMD-SHELL", "curl -fsS http://localhost:8080${var.liveness_check_path} || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 2
      startPeriod = 60
    }

    stopTimeout = 60

    dependsOn = [
      {
        containerName = local.log_router_name
        condition     = "START"
      },
      {
        containerName = local.appconfig_agent_name
        condition     = "START"
      },
    ]

    logConfiguration = {
      logDriver = "awsfirelens"
      options = {
        Name        = "loki"
        Host        = var.loki_host
        Port        = tostring(var.loki_port)
        labels      = "environment=${var.environment},service=api"
        line_format = "json"
      }
    }
  }

  worker_container_base = {
    name           = local.worker_container_name
    image          = var.backend_image_uri
    essential      = true
    command        = var.worker_command
    mountPoints    = []
    portMappings   = []
    systemControls = []
    volumesFrom    = []

    environment = [for name, value in merge(var.worker_environment, local.appconfig_client_environment) : {
      name  = name
      value = value
    }]

    secrets = [for name, value_from in var.worker_secrets : {
      name      = name
      valueFrom = value_from
    }]

    stopTimeout = 60

    dependsOn = [
      {
        containerName = local.log_router_name
        condition     = "START"
      },
      {
        containerName = local.appconfig_agent_name
        condition     = "START"
      },
    ]

    logConfiguration = {
      logDriver = "awsfirelens"
      options = {
        Name        = "loki"
        Host        = var.loki_host
        Port        = tostring(var.loki_port)
        labels      = "environment=${var.environment},service=worker"
        line_format = "json"
      }
    }
  }
}

data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_region" "current" {}

resource "aws_iam_role" "execution" {
  name               = "${var.name_prefix}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "execution_parameters" {
  count = length(local.all_secret_arns) > 0 ? 1 : 0

  statement {
    actions   = ["ssm:GetParameters"]
    resources = local.all_secret_arns
  }
}

resource "aws_iam_role_policy" "execution_parameters" {
  count = length(local.all_secret_arns) > 0 ? 1 : 0

  name   = "${var.name_prefix}-ecs-parameters"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_parameters[0].json
}

resource "aws_iam_role" "api_task" {
  name               = "${var.name_prefix}-api-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = var.common_tags
}

data "aws_iam_policy_document" "api_task" {
  statement {
    sid = "EcsExecChannels"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "UploadBucketList"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.uploads_bucket_name}"]
  }

  statement {
    sid = "UploadObjectAccess"
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = ["arn:aws:s3:::${var.uploads_bucket_name}/*"]
  }

  statement {
    sid       = "PublishDocumentJobs"
    actions   = ["sqs:GetQueueAttributes", "sqs:SendMessage"]
    resources = [var.document_jobs_queue_arn]
  }

  statement {
    sid = "ReadRuntimeConfiguration"
    actions = [
      "appconfig:StartConfigurationSession",
      "appconfig:GetLatestConfiguration",
    ]
    resources = [var.appconfig_configuration_arn]
  }
}

resource "aws_iam_role_policy" "api_task" {
  name   = "${var.name_prefix}-api-task-policy"
  role   = aws_iam_role.api_task.id
  policy = data.aws_iam_policy_document.api_task.json
}

resource "aws_iam_role" "worker_task" {
  name               = "${var.name_prefix}-worker-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = var.common_tags
}

data "aws_iam_policy_document" "worker_task" {
  statement {
    sid = "EcsExecChannels"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ReadUploadObjects"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.uploads_bucket_name}/*"]
  }

  statement {
    sid = "ConsumeDocumentJobs"
    actions = [
      "sqs:ChangeMessageVisibility",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ReceiveMessage",
    ]
    resources = [var.document_jobs_queue_arn]
  }

  statement {
    sid = "ReadRuntimeConfiguration"
    actions = [
      "appconfig:StartConfigurationSession",
      "appconfig:GetLatestConfiguration",
    ]
    resources = [var.appconfig_configuration_arn]
  }
}

resource "aws_iam_role_policy" "worker_task" {
  name   = "${var.name_prefix}-worker-task-policy"
  role   = aws_iam_role.worker_task.id
  policy = data.aws_iam_policy_document.worker_task.json
}

resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-cluster"

  tags = var.common_tags
}

resource "aws_ecs_task_definition" "api" {
  family                   = "${var.name_prefix}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.api_task.arn
  enable_fault_injection   = false
  container_definitions    = jsonencode([local.api_container, local.appconfig_agent_container, local.log_router_container])

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  tags = var.common_tags

  # 최초 Service 생성용 정의. 이후 실행 사양/컨테이너 설정은 앱 저장소·CD 소유다.
  # 기존 정의를 유지하여 관리 경계 변경만으로 Task를 재배포하지 않는다.
  lifecycle {
    ignore_changes = all
  }
}

resource "aws_ecs_task_definition" "worker" {
  family                   = "${var.name_prefix}-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.worker_task.arn
  enable_fault_injection   = false
  container_definitions    = jsonencode([local.worker_container_base, local.appconfig_agent_container, local.log_router_container])

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  tags = var.common_tags

  lifecycle {
    ignore_changes = all
  }
}

resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Public entry point for the API ALB"
  vpc_id      = var.vpc_id

  revoke_rules_on_delete = true

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-alb-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "Public HTTP access"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80

  tags = var.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  count = local.https_enabled ? 1 : 0

  security_group_id = aws_security_group.alb.id
  description       = "Public HTTPS access"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443

  tags = var.common_tags
}

resource "aws_vpc_security_group_egress_rule" "alb_to_api" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward API requests to ECS tasks"
  referenced_security_group_id = var.api_security_group_id
  from_port                    = 8080
  ip_protocol                  = "tcp"
  to_port                      = 8080

  tags = var.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "api_from_alb" {
  security_group_id            = var.api_security_group_id
  description                  = "API requests from the ALB"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 8080
  ip_protocol                  = "tcp"
  to_port                      = 8080

  tags = var.common_tags
}

resource "aws_lb" "api" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids
  idle_timeout       = 120

  tags = var.common_tags
}

resource "aws_lb_target_group" "api" {
  name                 = "${var.name_prefix}-api-tg"
  port                 = 8080
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 60

  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    port                = "traffic-port"
    interval            = var.api_health_check_interval_seconds
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-399"
  }

  tags = var.common_tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = local.https_enabled ? "redirect" : "forward"
    target_group_arn = local.https_enabled ? null : aws_lb_target_group.api.arn

    dynamic "redirect" {
      for_each = local.https_enabled ? [1] : []

      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  tags = var.common_tags
}

resource "aws_lb_listener" "https" {
  count = local.https_enabled ? 1 : 0

  load_balancer_arn = aws_lb.api.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }

  tags = var.common_tags
}

resource "aws_ecs_service" "api" {
  name                               = "${var.name_prefix}-api"
  cluster                            = aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.api.arn
  desired_count                      = var.api_desired_count
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  health_check_grace_period_seconds  = var.api_health_check_grace_period_seconds
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  enable_execute_command             = true

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [var.api_security_group_id, var.monitoring_client_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = local.api_container_name
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.http, aws_lb_listener.https]

  tags = var.common_tags

  # CD가 선택한 실행 Revision은 Terraform apply로 되돌리지 않는다.
  # desired_count는 아직 Terraform 관리이며 의도적으로 무시하지 않는다.
  lifecycle {
    ignore_changes = [task_definition]
  }
}

resource "aws_ecs_service" "worker" {
  name                               = "${var.name_prefix}-worker"
  cluster                            = aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.worker.arn
  desired_count                      = var.worker_desired_count
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  enable_execute_command             = true

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [var.worker_security_group_id, var.monitoring_client_security_group_id]
    assign_public_ip = false
  }

  tags = var.common_tags

  lifecycle {
    ignore_changes = [task_definition]
  }
}
