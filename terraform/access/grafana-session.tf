data "terraform_remote_state" "monitoring" {
  backend = "s3"
  config = {
    bucket = "zipsai-v2-terraform-state"
    key    = "monitoring/terraform.tfstate"
    region = local.region
  }
}

locals {
  monitoring_instance_arn = "${local.prefix}:ec2:${local.region}:${local.account}:instance/${data.terraform_remote_state.monitoring.outputs.instance_id}"
}

# A fixed server port prevents reuse of the AWS generic forwarding document to
# reach Prometheus, Loki, SSH or another internal service on the same host.
resource "aws_ssm_document" "grafana_forward" {
  name            = "zipsai-grafana-port-forward"
  document_type   = "Session"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Forward only Grafana on the monitoring host; no shell or remote host selection"
    sessionType   = "Port"
    parameters = {
      localPortNumber = {
        type           = "String"
        description    = "Local browser port"
        default        = "3000"
        allowedPattern = "^([1-9]|[1-9][0-9]{1,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$"
      }
    }
    properties = {
      portNumber      = "3000"
      type            = "LocalPortForwarding"
      localPortNumber = "{{ localPortNumber }}"
    }
  })
  tags = { Project = "zipsai", ManagedBy = "Terraform", Component = "team-access" }
}

resource "aws_iam_policy" "grafana_forward" {
  name = "Zipsai-GrafanaPortForward"
  # Preserve the original description; changing it would replace this policy.
  description = "Grafana-only monitoring session and own-session cleanup; no SendCommand or shell grant"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AssumeIsolatedGrafanaRole"
      Effect   = "Allow"
      Action   = ["sts:AssumeRole"]
      Resource = aws_iam_role.grafana_viewer.arn
    }]
  })
  tags = { Project = "zipsai", ManagedBy = "Terraform", Component = "team-access" }
}

# Existing DB viewer permissions allow generic forwarding documents. Do not union
# monitoring StartSession permissions into those users: use an isolated role.
resource "aws_iam_role" "grafana_viewer" {
  name                 = "zipsai-grafana-viewer"
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
  tags = { Project = "zipsai", ManagedBy = "Terraform", Component = "team-access" }
}

resource "aws_iam_role_policy" "grafana_session" {
  name = "grafana-session-only"
  role = aws_iam_role.grafana_viewer.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StartGrafanaSessionOnly"
        Effect   = "Allow"
        Action   = ["ssm:StartSession"]
        Resource = [local.monitoring_instance_arn, aws_ssm_document.grafana_forward.arn]
        # Check the requested/default document too; instance access alone is not enough.
        Condition = { BoolIfExists = { "ssm:SessionDocumentAccessCheck" = "true" } }
      },
      {
        Sid      = "OpenOwnSessionChannel"
        Effect   = "Allow"
        Action   = ["ssmmessages:OpenDataChannel"]
        Resource = "${local.prefix}:ssm:${local.region}:${local.account}:session/$${aws:userid}-*"
      },
      {
        Sid      = "EndOwnMonitoringSessionsOnly"
        Effect   = "Allow"
        Action   = ["ssm:TerminateSession", "ssm:ResumeSession"]
        Resource = "${local.prefix}:ssm:${local.region}:${local.account}:session/*"
        Condition = { StringLike = {
          "ssm:resourceTag/aws:ssmmessages:session-id" = "$${aws:userid}*"
          "ssm:resourceTag/aws:ssmmessages:target-id"  = data.terraform_remote_state.monitoring.outputs.instance_id
        } }
      }
    ]
  })
}

resource "aws_iam_group_policy_attachment" "grafana_forward" {
  group      = aws_iam_group.log_viewers.name
  policy_arn = aws_iam_policy.grafana_forward.arn
}

output "grafana_port_forward_command" {
  description = "Use the grafana role profile from README, not the IAM user's base profile."
  value       = "aws --profile grafana --region ${local.region} ssm start-session --target ${data.terraform_remote_state.monitoring.outputs.instance_id} --document-name ${aws_ssm_document.grafana_forward.name} --parameters '{\"localPortNumber\":[\"3000\"]}'"
}

output "grafana_role_arn" { value = aws_iam_role.grafana_viewer.arn }
