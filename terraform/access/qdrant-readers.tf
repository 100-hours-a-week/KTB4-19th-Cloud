locals {
  qdrant_reader_environments = {
    staging = { local_port = "26333" }
    prod    = { local_port = "36333" }
  }
  qdrant_reader_tags = { Project = "zipsai", ManagedBy = "Terraform", Component = "ai-qdrant-access" }
}

# Reuse the existing AI-only group without changing V1 policy or membership.
data "aws_iam_group" "qdrant_readers" {
  group_name = "zipsai-prod-qdrant-readers"
}

data "aws_instance" "qdrant" {
  for_each = local.qdrant_reader_environments
  filter {
    name   = "tag:Name"
    values = ["zipsai-${each.key}-qdrant"]
  }
  filter {
    name   = "tag:Project"
    values = ["zipsai"]
  }
  filter {
    name   = "instance-state-name"
    values = ["running", "stopped"]
  }
}

resource "aws_ssm_document" "qdrant_forward" {
  for_each        = local.qdrant_reader_environments
  name            = "zipsai-${each.key}-qdrant-reader-forward"
  document_type   = "Session"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Forward only ${each.key} Qdrant 6333; use its read-only API key separately"
    sessionType   = "Port"
    parameters = {
      localPortNumber = {
        type           = "String"
        default        = each.value.local_port
        allowedPattern = "^([1-9]|[1-9][0-9]{1,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$"
      }
    }
    properties = {
      type            = "LocalPortForwarding"
      portNumber      = "6333"
      localPortNumber = "{{ localPortNumber }}"
    }
  })
  tags = merge(local.qdrant_reader_tags, { Environment = each.key })
}

resource "aws_iam_role" "qdrant_reader" {
  for_each             = local.qdrant_reader_environments
  name                 = "zipsai-${each.key}-qdrant-reader"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "${local.prefix}:iam::${local.account}:root" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "sts:RoleSessionName" = "$${aws:username}" } }
    }]
  })
  tags = merge(local.qdrant_reader_tags, { Environment = each.key })
}

resource "aws_iam_role_policy" "qdrant_session" {
  for_each = local.qdrant_reader_environments
  name     = "qdrant-session-only"
  role     = aws_iam_role.qdrant_reader[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "StartOnlyThisEnvironmentQdrant"
        Effect    = "Allow"
        Action    = ["ssm:StartSession"]
        Resource  = [data.aws_instance.qdrant[each.key].arn, aws_ssm_document.qdrant_forward[each.key].arn]
        Condition = { BoolIfExists = { "ssm:SessionDocumentAccessCheck" = "true" } }
      },
      {
        Sid      = "OpenOwnSessionChannel"
        Effect   = "Allow"
        Action   = ["ssmmessages:OpenDataChannel"]
        Resource = "${local.prefix}:ssm:${local.region}:${local.account}:session/$${aws:userid}-*"
      },
      {
        Sid      = "ManageOwnQdrantSessions"
        Effect   = "Allow"
        Action   = ["ssm:TerminateSession", "ssm:ResumeSession"]
        Resource = "${local.prefix}:ssm:${local.region}:${local.account}:session/*"
        Condition = { StringLike = {
          "ssm:resourceTag/aws:ssmmessages:session-id" = "$${aws:userid}*"
          "ssm:resourceTag/aws:ssmmessages:target-id"  = data.aws_instance.qdrant[each.key].id
        } }
      }
    ]
  })
}

resource "aws_iam_policy" "assume_qdrant_reader" {
  name        = "Zipsai-V2QdrantReaderRoles"
  description = "AI team assumes isolated V2 Qdrant tunnel roles; API keys managed separately"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sts:AssumeRole"]
      Resource = [for role in aws_iam_role.qdrant_reader : role.arn]
    }]
  })
  tags = local.qdrant_reader_tags
}

resource "aws_iam_group_policy_attachment" "qdrant_readers" {
  group      = data.aws_iam_group.qdrant_readers.group_name
  policy_arn = aws_iam_policy.assume_qdrant_reader.arn
}

output "qdrant_reader_connections" {
  value = { for environment, config in local.qdrant_reader_environments : environment => {
    role_arn          = aws_iam_role.qdrant_reader[environment].arn
    instance_id       = data.aws_instance.qdrant[environment].id
    document_name     = aws_ssm_document.qdrant_forward[environment].name
    dashboard_url     = "http://localhost:${config.local_port}/dashboard"
    readonly_key_path = "/zipsai/${environment}/ai/qdrant-read-only-api-key"
  } }
}
