locals {
  data_viewer_nodes = concat(
    [for instance in data.aws_instance.mysql_primary : instance.arn],
    [for instance in data.aws_instance.qdrant : instance.arn]
  )
  data_viewer_documents = concat(
    [for document in aws_ssm_document.mysql_forward : document.arn],
    [for document in aws_ssm_document.qdrant_forward : document.arn]
  )
  data_viewer_tags = { Project = "zipsai", ManagedBy = "Terraform", Component = "team-data-access" }
}

# A single role keeps the user's legacy generic forwarding grants out of V2 sessions.
resource "aws_iam_role" "data_viewer" {
  name                 = "zipsai-v2-data-viewer"
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
  tags = local.data_viewer_tags
}

resource "aws_iam_role_policy" "data_viewer_session" {
  name = "v2-database-fixed-port-sessions"
  role = aws_iam_role.data_viewer.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "StartFixedDatabasePortSessions"
        Effect    = "Allow"
        Action    = ["ssm:StartSession"]
        Resource  = concat(local.data_viewer_nodes, local.data_viewer_documents)
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
          "ssm:resourceTag/aws:ssmmessages:target-id" = concat(
            [for instance in data.aws_instance.mysql_primary : instance.id],
            [for instance in data.aws_instance.qdrant : instance.id]
          )
        } }
      }
    ]
  })
}

resource "aws_iam_policy" "assume_data_viewer" {
  name        = "Zipsai-V2UnifiedDataViewerRole"
  description = "Team members assume one isolated V2 MySQL and Qdrant tunnel role"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sts:AssumeRole"]
      Resource = aws_iam_role.data_viewer.arn
    }]
  })
  tags = local.data_viewer_tags
}

resource "aws_iam_group_policy_attachment" "data_viewers" {
  group      = aws_iam_group.log_viewers.name
  policy_arn = aws_iam_policy.assume_data_viewer.arn
}

output "unified_data_viewer_role_arn" {
  value = aws_iam_role.data_viewer.arn
}
