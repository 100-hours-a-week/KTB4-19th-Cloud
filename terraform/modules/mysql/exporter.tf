# Opt in per environment. All V1 instances remain untouched.
resource "aws_ssm_document" "mysql_exporter" {
  count           = var.enable_exporter_configuration ? 1 : 0
  name            = "${var.name_prefix}-mysql-exporter-config"
  document_type   = "Command"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Configure native MySQL monitoring; preserve existing credentials and files"
    parameters = {
      PasswordParameter = {
        type              = "String"
        interpolationType = "ENV_VAR"
        allowedValues     = [var.exporter_password_parameter_name]
      }
      ExpectedInstanceId = {
        type              = "String"
        interpolationType = "ENV_VAR"
        allowedValues     = [for node in aws_instance.mysql : node.id]
      }
    }
    mainSteps = [{
      action       = "aws:runShellScript"
      name         = "configureMySQLExporter"
      precondition = { StringEquals = ["platformType", "Linux"] }
      inputs = {
        timeoutSeconds = "300"
        runCommand = [
          "set -eu",
          "python3 -c \"$(printf '%s' '${base64encode(file("${path.module}/scripts/configure_mysql_exporter.py"))}' | base64 --decode)\""
        ]
      }
    }]
  })
  tags = var.common_tags
  lifecycle {
    precondition {
      condition = var.exporter_password_parameter_name == null ? false : anytrue([
        for arn in var.secret_parameter_arns : endswith(arn, ":parameter${var.exporter_password_parameter_name}")
      ])
      error_message = "Exporter configuration requires an existing password parameter included in node IAM permissions."
    }
  }
}

resource "aws_ssm_association" "mysql_exporter" {
  for_each         = var.enable_exporter_configuration ? local.nodes : {}
  association_name = "${var.name_prefix}-mysql-exporter-${each.key}"
  name             = aws_ssm_document.mysql_exporter[0].name
  document_version = aws_ssm_document.mysql_exporter[0].latest_version
  parameters = {
    PasswordParameter  = var.exporter_password_parameter_name
    ExpectedInstanceId = aws_instance.mysql[each.key].id
  }
  targets {
    key    = "InstanceIds"
    values = [aws_instance.mysql[each.key].id]
  }
  wait_for_success_timeout_seconds = 300
}
