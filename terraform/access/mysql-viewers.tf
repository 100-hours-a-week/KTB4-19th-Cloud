locals {
  mysql_viewer_environments = {
    staging = { local_port = "13306" }
    prod    = { local_port = "23306" }
  }
  mysql_viewer_tags = { Project = "zipsai", ManagedBy = "Terraform", Component = "team-db-access" }
}

# Resolve the existing Primary; never create/replace a database from this Root.
data "aws_instance" "mysql_primary" {
  for_each = local.mysql_viewer_environments
  filter {
    name   = "tag:Name"
    values = ["zipsai-${each.key}-mysql-primary"]
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

resource "aws_ssm_document" "mysql_forward" {
  for_each        = local.mysql_viewer_environments
  name            = "zipsai-${each.key}-mysql-viewer-forward"
  document_type   = "Session"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Forward ${each.key} MySQL only; database credentials grant read-only access separately"
    sessionType   = "Port"
    parameters = {
      localPortNumber = {
        type           = "String"
        default        = each.value.local_port
        allowedPattern = "^([1-9]|[1-9][0-9]{1,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$"
      }
    }
    properties = {
      portNumber      = "3306"
      type            = "LocalPortForwarding"
      localPortNumber = "{{ localPortNumber }}"
    }
  })
  tags = merge(local.mysql_viewer_tags, { Environment = each.key })
}

resource "aws_iam_role" "mysql_viewer" {
  for_each             = local.mysql_viewer_environments
  name                 = "zipsai-${each.key}-mysql-viewer"
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
  tags = merge(local.mysql_viewer_tags, { Environment = each.key })
}

resource "aws_iam_role_policy" "mysql_session" {
  for_each = local.mysql_viewer_environments
  name     = "mysql-session-only"
  role     = aws_iam_role.mysql_viewer[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "StartOnlyThisEnvironmentMySQL"
        Effect    = "Allow"
        Action    = ["ssm:StartSession"]
        Resource  = [data.aws_instance.mysql_primary[each.key].arn, aws_ssm_document.mysql_forward[each.key].arn]
        Condition = { BoolIfExists = { "ssm:SessionDocumentAccessCheck" = "true" } }
      },
      {
        Sid      = "OpenOwnSessionChannel"
        Effect   = "Allow"
        Action   = ["ssmmessages:OpenDataChannel"]
        Resource = "${local.prefix}:ssm:${local.region}:${local.account}:session/$${aws:userid}-*"
      },
      {
        Sid      = "ManageOwnDatabaseSessions"
        Effect   = "Allow"
        Action   = ["ssm:TerminateSession", "ssm:ResumeSession"]
        Resource = "${local.prefix}:ssm:${local.region}:${local.account}:session/*"
        Condition = { StringLike = {
          "ssm:resourceTag/aws:ssmmessages:session-id" = "$${aws:userid}*"
          "ssm:resourceTag/aws:ssmmessages:target-id"  = data.aws_instance.mysql_primary[each.key].id
        } }
      }
    ]
  })
}

# All five existing team members; do not mutate existing V1 DB group membership.
resource "aws_iam_policy" "assume_mysql_viewer" {
  name        = "Zipsai-V2MySQLViewerRoles"
  description = "Assume isolated V2 staging and prod database tunnel roles; no SQL privileges"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sts:AssumeRole"]
      Resource = [for role in aws_iam_role.mysql_viewer : role.arn]
    }]
  })
  tags = local.mysql_viewer_tags
}

resource "aws_iam_group_policy_attachment" "mysql_viewers" {
  group      = aws_iam_group.log_viewers.name
  policy_arn = aws_iam_policy.assume_mysql_viewer.arn
}

output "mysql_viewer_connections" {
  description = "Tunnel settings only. A separate MySQL SELECT/SHOW VIEW account is required."
  value = { for environment, settings in local.mysql_viewer_environments : environment => {
    role_arn        = aws_iam_role.mysql_viewer[environment].arn
    instance_id     = data.aws_instance.mysql_primary[environment].id
    document_name   = aws_ssm_document.mysql_forward[environment].name
    local_port      = settings.local_port
    database        = "zipsai"
    server_uuid_sql = "SELECT @@hostname, @@server_uuid, DATABASE();"
  } }
}
