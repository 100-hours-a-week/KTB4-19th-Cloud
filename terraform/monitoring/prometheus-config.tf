locals {
  prometheus_config_base64 = base64encode(file("${path.root}/../../monitoring/prometheus.yml"))
}

resource "aws_ssm_document" "prometheus_config" {
  name            = "zipsai-monitoring-prometheus-config"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Validate and deploy the Zipsai Prometheus scrape configuration"
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "deployPrometheusConfig"
        inputs = {
          timeoutSeconds = "300"
          runCommand = [
            "set -eu",
            "temp_file=$(mktemp)",
            "trap 'rm -f \"$temp_file\"' EXIT",
            "printf '%s' '${local.prometheus_config_base64}' | base64 --decode > \"$temp_file\"",
            "chmod 0644 \"$temp_file\"",
            "docker run --rm --entrypoint /bin/promtool -v \"$temp_file:/etc/prometheus/prometheus.yml:ro\" prom/prometheus:v3.14.0 check config /etc/prometheus/prometheus.yml",
            "cat \"$temp_file\" > /opt/zipsai-monitoring/config/prometheus.yml",
            "chown root:root /opt/zipsai-monitoring/config/prometheus.yml",
            "chmod 0644 /opt/zipsai-monitoring/config/prometheus.yml",
            "curl --fail --silent --show-error -X POST http://127.0.0.1:9090/-/reload",
          ]
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_ssm_association" "prometheus_config" {
  name             = aws_ssm_document.prometheus_config.name
  document_version = aws_ssm_document.prometheus_config.latest_version

  targets {
    key    = "InstanceIds"
    values = [module.monitoring.instance_id]
  }

  wait_for_success_timeout_seconds = 300
}
