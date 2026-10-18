locals {
  monitoring_stack_deploy_script = templatefile("${path.module}/templates/deploy-stack.sh.tftpl", {
    compose_base64     = base64encode(file("${path.root}/../../monitoring/docker-compose.yml"))
    loki_base64        = base64encode(file("${path.root}/../../monitoring/loki.yml"))
    datasources_base64 = base64encode(file("${path.root}/../../monitoring/grafana-datasources.yml"))
    prometheus_seed    = base64encode(file("${path.root}/../../monitoring/prometheus-bootstrap.yml"))
    prometheus_image   = yamldecode(file("${path.root}/../../monitoring/docker-compose.yml")).services.prometheus.image
  })
}

resource "aws_ssm_document" "stack_config" {
  name            = "zipsai-monitoring-stack-config"
  document_type   = "Command"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Deploy monitoring runtime configuration without replacing the EC2 host"
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "deployMonitoringStack"
      inputs = {
        timeoutSeconds = "1800"
        runCommand     = ["bash -se <<'ZipsaiMonitoringDeploy'\n${local.monitoring_stack_deploy_script}\nZipsaiMonitoringDeploy"]
      }
    }]
  })
  tags = local.common_tags
}

resource "aws_ssm_association" "stack_config" {
  name             = aws_ssm_document.stack_config.name
  document_version = aws_ssm_document.stack_config.latest_version
  targets {
    key    = "InstanceIds"
    values = [module.monitoring.instance_id]
  }
  wait_for_success_timeout_seconds = 1800
}
