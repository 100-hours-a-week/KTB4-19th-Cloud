locals {
  # Keep CloudWatch and add Loki collection for both environments.
  ai_observability_targets = {
    for target in setproduct(["staging", "prod"], ["ai-api", "embedding", "qdrant"]) : "${target[0]}-${target[1]}" => {
      environment = target[0]
      service     = target[1]
    }
  }
  ai_metrics_targets = {
    for key, target in local.ai_observability_targets : key => target
    if target.service != "qdrant"
  }
  ai_collector_script  = base64encode(file("${path.module}/templates/deploy-ai-observability.py"))
  ai_collector_compose = base64encode(file("${path.root}/../../monitoring/ai-logs-compose.yml"))
}

data "aws_instance" "ai_observability" {
  for_each = local.ai_observability_targets
  filter {
    name   = "tag:Name"
    values = ["zipsai-${each.value.environment}-${each.value.service}"]
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

resource "aws_vpc_security_group_ingress_rule" "ai_metrics" {
  for_each                     = local.ai_metrics_targets
  security_group_id            = one(data.aws_instance.ai_observability[each.key].vpc_security_group_ids)
  referenced_security_group_id = data.terraform_remote_state.network.outputs.monitoring_server_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
  description                  = "Private Prometheus scrape of ${each.key}"
  tags                         = local.common_tags
}

resource "aws_vpc_security_group_egress_rule" "ai_metrics" {
  for_each                     = local.ai_metrics_targets
  security_group_id            = data.terraform_remote_state.network.outputs.monitoring_server_security_group_id
  referenced_security_group_id = one(data.aws_instance.ai_observability[each.key].vpc_security_group_ids)
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
  description                  = "Scrape ${each.key} only"
  tags                         = local.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "ai_loki" {
  for_each                     = local.ai_observability_targets
  security_group_id            = data.terraform_remote_state.network.outputs.monitoring_server_security_group_id
  referenced_security_group_id = one(data.aws_instance.ai_observability[each.key].vpc_security_group_ids)
  ip_protocol                  = "tcp"
  from_port                    = 3100
  to_port                      = 3100
  description                  = "Private Loki ingestion from ${each.key}"
  tags                         = local.common_tags
}

resource "aws_ssm_document" "ai_log_collector" {
  for_each        = local.ai_observability_targets
  name            = "zipsai-${each.key}-loki-collector"
  document_type   = "Command"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Deploy independent AI Loki collector while retaining CloudWatch driver"
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "deployCollector"
      inputs = {
        timeoutSeconds = "600"
        runCommand = [join("\n", [
          "set -eu",
          "python3 - '${base64encode(templatefile("${path.root}/../../monitoring/ai-logs.alloy.tftpl", each.value))}' '${local.ai_collector_compose}' <<'PY'",
          "import base64",
          "exec(compile(base64.b64decode('${local.ai_collector_script}'), '<ai-log-collector>', 'exec'))",
          "PY"
        ])]
      }
    }]
  })
  tags = local.common_tags
}

resource "aws_ssm_association" "ai_log_collector" {
  for_each         = local.ai_observability_targets
  name             = aws_ssm_document.ai_log_collector[each.key].name
  document_version = aws_ssm_document.ai_log_collector[each.key].latest_version
  depends_on       = [aws_vpc_security_group_ingress_rule.ai_loki]
  targets {
    key    = "InstanceIds"
    values = [data.aws_instance.ai_observability[each.key].id]
  }
  wait_for_success_timeout_seconds = 600
}
