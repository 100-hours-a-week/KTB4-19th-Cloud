# Existing group, policy and attachment adopted without replacing CloudWatch access.
# IAM users and membership remain unchanged; no exclusive membership resource here.
resource "aws_iam_group" "log_viewers" {
  name = "zipsai-prod-log-viewers"
  path = "/"
  lifecycle { prevent_destroy = true }
}

locals {
  legacy_log_arns = [for service in ["backend", "mysql", "qdrant", "ai-api", "embedding", "nginx"] :
    "${local.prefix}:logs:${local.region}:${local.account}:log-group:/zipsai/prod/${service}:*"
  ]
}

resource "aws_iam_policy" "production_logs" {
  name        = "Zipsai-ReadProductionLogs"
  path        = "/"
  description = "Zipsai-ReadProductionLogs"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListCloudWatchLogGroupsAndStreams"
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups", "logs:DescribeLogStreams"]
        Resource = "*"
      },
      {
        Sid      = "ReadOnlyZipsaiProductionLogs"
        Effect   = "Allow"
        Action   = ["logs:GetLogEvents", "logs:FilterLogEvents"]
        Resource = local.legacy_log_arns
      },
      {
        Sid      = "RunZipsaiLogsInsightsQueries"
        Effect   = "Allow"
        Action   = ["logs:StartQuery"]
        Resource = local.legacy_log_arns
      },
      {
        Sid      = "ReadLogsInsightsQueryResults"
        Effect   = "Allow"
        Action   = ["logs:GetQueryResults", "logs:StopQuery", "logs:GetLogRecord"]
        Resource = "*"
      },
      {
        Sid    = "ReadCloudWatchDashboardsAndMetrics"
        Effect = "Allow"
        Action = ["cloudwatch:GetDashboard", "cloudwatch:ListDashboards", "cloudwatch:GetMetricData",
        "cloudwatch:GetMetricStatistics", "cloudwatch:ListMetrics", "cloudwatch:DescribeAlarms", "cloudwatch:DescribeAlarmHistory"]
        Resource = "*"
      }
    ]
  })
  lifecycle { prevent_destroy = true }
}

resource "aws_iam_group_policy_attachment" "production_logs" {
  group      = aws_iam_group.log_viewers.name
  policy_arn = aws_iam_policy.production_logs.arn
}

import {
  to = aws_iam_group.log_viewers
  id = "zipsai-prod-log-viewers"
}
import {
  to = aws_iam_policy.production_logs
  id = "${local.prefix}:iam::${local.account}:policy/Zipsai-ReadProductionLogs"
}
import {
  to = aws_iam_group_policy_attachment.production_logs
  id = "zipsai-prod-log-viewers/${local.prefix}:iam::${local.account}:policy/Zipsai-ReadProductionLogs"
}
