locals {
  nightly_shutdown_name = "${local.name_prefix}-nightly-shutdown"
  nightly_shutdown_instance_ids = var.enable_v2_apps ? concat(
    [module.mysql.instance_ids.primary, module.redis.instance_id],
    [for role in ["ai-api", "embedding", "qdrant"] : module.ai.deployment_contract[role].instance_id]
  ) : []
  nightly_shutdown_services = var.enable_v2_apps ? [module.ecs.api_service_name, module.ecs.worker_service_name] : []
  nightly_shutdown_service_arns = [for name in local.nightly_shutdown_services :
    "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:service/${split("/", module.ecs.cluster_arn)[1]}/${name}"
  ]
}

resource "aws_iam_role" "nightly_shutdown_automation" {
  count = var.enable_v2_apps ? 1 : 0
  name  = "${local.nightly_shutdown_name}-automation"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow", Principal = { Service = "ssm.amazonaws.com" }, Action = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:automation-execution/*" }
      }
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy" "nightly_shutdown_automation" {
  count = var.enable_v2_apps ? 1 : 0
  name  = "staging-stop-only"
  role  = aws_iam_role.nightly_shutdown_automation[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow", Action = ["ec2:DescribeInstances"], Resource = "*"
      },
      {
        Effect    = "Allow", Action = ["ec2:StopInstances"]
        Resource  = [for id in local.nightly_shutdown_instance_ids : "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/${id}"]
        Condition = { StringEquals = { "ec2:ResourceTag/Environment" = "staging", "ec2:ResourceTag/Project" = "zipsai" } }
      },
      {
        Effect   = "Allow", Action = ["ecs:UpdateService", "ecs:DescribeServices"]
        Resource = local.nightly_shutdown_service_arns
      },
      {
        Effect    = "Allow", Action = ["ecs:ListTasks"], Resource = "*"
        Condition = { ArnEquals = { "ecs:cluster" = module.ecs.cluster_arn } }
      },
      {
        Effect   = "Allow", Action = ["ecs:DescribeTasks"]
        Resource = "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:task/${split("/", module.ecs.cluster_arn)[1]}/*"
      }
    ]
  })
}

resource "aws_ssm_document" "nightly_shutdown" {
  count           = var.enable_v2_apps ? 1 : 0
  name            = local.nightly_shutdown_name
  document_type   = "Automation"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "0.3"
    description   = "Stop staging API/worker, wait for tasks, then gracefully stop staging EC2 only"
    assumeRole    = aws_iam_role.nightly_shutdown_automation[0].arn
    parameters = {
      DryRun = { type = "String", default = "true", allowedValues = ["true", "false"] }
    }
    mainSteps = [{
      name = "stopStaging", action = "aws:executeScript", timeoutSeconds = 600, maxAttempts = 1
      inputs = {
        Runtime = "python3.11", Handler = "shutdown"
        Script  = file("${path.module}/scripts/nightly_shutdown.py")
        InputPayload = {
          region       = var.aws_region, environment = local.environment
          instance_ids = local.nightly_shutdown_instance_ids
          cluster      = module.ecs.cluster_arn, services = local.nightly_shutdown_services
          dry_run      = "{{ DryRun }}"
        }
      }
    }]
  })
  tags       = local.common_tags
  depends_on = [aws_iam_role_policy.nightly_shutdown_automation[0]]
}

resource "aws_scheduler_schedule_group" "staging_power" {
  count = var.enable_v2_apps ? 1 : 0
  name  = "${local.name_prefix}-power"
  tags  = local.common_tags
}

resource "aws_iam_role" "nightly_shutdown_scheduler" {
  count = var.enable_v2_apps ? 1 : 0
  name  = "${local.nightly_shutdown_name}-scheduler"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow", Principal = { Service = "scheduler.amazonaws.com" }, Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          "aws:SourceArn"     = aws_scheduler_schedule_group.staging_power[0].arn
        }
      }
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy" "nightly_shutdown_scheduler" {
  count = var.enable_v2_apps ? 1 : 0
  name  = "start-staging-shutdown-only"
  role  = aws_iam_role.nightly_shutdown_scheduler[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow", Action = ["ssm:StartAutomationExecution"]
        Resource = [
          "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:automation-definition/${aws_ssm_document.nightly_shutdown[0].name}:*",
          "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:document/${aws_ssm_document.nightly_shutdown[0].name}",
          "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:automation-execution/*"
        ]
      },
      {
        Effect    = "Allow", Action = ["iam:PassRole"], Resource = aws_iam_role.nightly_shutdown_automation[0].arn
        Condition = { StringEquals = { "iam:PassedToService" = "ssm.amazonaws.com" } }
      }
    ]
  })
}

resource "aws_scheduler_schedule" "nightly_shutdown" {
  count                        = var.enable_v2_apps ? 1 : 0
  name                         = local.nightly_shutdown_name
  group_name                   = aws_scheduler_schedule_group.staging_power[0].name
  description                  = "Daily 01:00 Asia/Seoul staging stop; manual start only"
  state                        = "ENABLED"
  schedule_expression          = "cron(0 1 * * ? *)"
  schedule_expression_timezone = "Asia/Seoul"
  flexible_time_window { mode = "OFF" }
  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ssm:startAutomationExecution"
    role_arn = aws_iam_role.nightly_shutdown_scheduler[0].arn
    input = jsonencode({
      DocumentName    = aws_ssm_document.nightly_shutdown[0].name
      DocumentVersion = aws_ssm_document.nightly_shutdown[0].latest_version
      Parameters      = { DryRun = ["false"] }
    })
    retry_policy {
      maximum_event_age_in_seconds = 300
      maximum_retry_attempts       = 1
    }
  }
  depends_on = [aws_iam_role_policy.nightly_shutdown_scheduler[0]]
}

output "staging_nightly_shutdown" {
  description = "Nightly staging stop only. No automatic start schedule is provisioned."
  value = var.enable_v2_apps ? {
    schedule_name       = aws_scheduler_schedule.nightly_shutdown[0].name
    schedule_group      = aws_scheduler_schedule_group.staging_power[0].name
    timezone            = "Asia/Seoul", shutdown_time = "01:00"
    automation_document = aws_ssm_document.nightly_shutdown[0].name
    instance_ids        = local.nightly_shutdown_instance_ids
  } : null
}

moved {
  from = aws_iam_role.nightly_shutdown_automation
  to   = aws_iam_role.nightly_shutdown_automation[0]
}

moved {
  from = aws_iam_role_policy.nightly_shutdown_automation
  to   = aws_iam_role_policy.nightly_shutdown_automation[0]
}

moved {
  from = aws_ssm_document.nightly_shutdown
  to   = aws_ssm_document.nightly_shutdown[0]
}

moved {
  from = aws_scheduler_schedule_group.staging_power
  to   = aws_scheduler_schedule_group.staging_power[0]
}

moved {
  from = aws_iam_role.nightly_shutdown_scheduler
  to   = aws_iam_role.nightly_shutdown_scheduler[0]
}

moved {
  from = aws_iam_role_policy.nightly_shutdown_scheduler
  to   = aws_iam_role_policy.nightly_shutdown_scheduler[0]
}

moved {
  from = aws_scheduler_schedule.nightly_shutdown
  to   = aws_scheduler_schedule.nightly_shutdown[0]
}
