data "aws_instance" "v3_grafana_management" {
  filter {
    name   = "tag:Name"
    values = ["zipsai-v3-eks-management"]
  }
  filter {
    name   = "instance-state-name"
    values = ["running", "stopped"]
  }
}

resource "aws_ssm_document" "grafana_v3_forward" {
  name            = "zipsai-v3-grafana-port-forward"
  document_type   = "Session"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Forward only the V3 Grafana loopback listener on the management host"
    sessionType   = "Port"
    parameters = {
      localPortNumber = {
        type           = "String"
        default        = "3000"
        allowedPattern = "^([1-9]|[1-9][0-9]{1,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$"
      }
    }
    properties = {
      portNumber      = "13000"
      type            = "LocalPortForwarding"
      localPortNumber = "{{ localPortNumber }}"
    }
  })
  tags = { Project = "zipsai", ManagedBy = "Terraform", Component = "team-access" }
}

resource "aws_iam_role_policy" "grafana_v3_session" {
  name = "grafana-v3-session-only"
  role = aws_iam_role.grafana_viewer.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "StartV3GrafanaSessionOnly"
        Effect    = "Allow"
        Action    = ["ssm:StartSession"]
        Resource  = [data.aws_instance.v3_grafana_management.arn, aws_ssm_document.grafana_v3_forward.arn]
        Condition = { BoolIfExists = { "ssm:SessionDocumentAccessCheck" = "true" } }
      },
      {
        Sid      = "EndOwnV3GrafanaSessionsOnly"
        Effect   = "Allow"
        Action   = ["ssm:TerminateSession", "ssm:ResumeSession"]
        Resource = "${local.prefix}:ssm:${local.region}:${local.account}:session/*"
        Condition = { StringLike = {
          "ssm:resourceTag/aws:ssmmessages:session-id" = "$${aws:userid}*"
          "ssm:resourceTag/aws:ssmmessages:target-id"  = data.aws_instance.v3_grafana_management.id
        } }
      }
    ]
  })
}

output "grafana_v3_port_forward_command" {
  description = "Use the existing grafana role profile; keep the terminal open and visit http://localhost:3000."
  value       = "aws --profile grafana --region ${local.region} ssm start-session --target ${data.aws_instance.v3_grafana_management.id} --document-name ${aws_ssm_document.grafana_v3_forward.name} --parameters '{\"localPortNumber\":[\"3000\"]}'"
}
