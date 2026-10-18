variable "enable_rehearsal_exporters" {
  description = "Configure V1 development exporters, preserving existing containers."
  type        = bool
  default     = false
}

variable "enable_production_exporters" {
  description = "Configure V1 production exporters only; never restart application containers."
  type        = bool
  default     = false
}

locals {
  v1_exporter_targets = {
    rehearsal = {
      enabled   = var.enable_rehearsal_exporters
      id        = aws_instance.rehearsal.id
      ip        = aws_instance.rehearsal.private_ip
      parameter = "/zipsai/staging/mysql/exporter-password"
    }
    production = {
      enabled   = var.enable_production_exporters
      id        = aws_instance.production.id
      ip        = aws_instance.production.private_ip
      parameter = "/zipsai/prod/mysql-v1/exporter-password"
    }
  }
  v1_exporter_scripts = {
    "configure_mysql_exporter.py" = base64encode(file("${path.module}/../modules/mysql/scripts/configure_mysql_exporter.py"))
    "configure_v1_exporters.py"   = base64encode(file("${path.module}/../modules/mysql/scripts/configure_v1_exporters.py"))
  }
}

resource "aws_ssm_document" "v1_exporters" {
  name            = "zipsai-v1-exporters-config"
  document_type   = "Command"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Configure V1 monitoring only; preserve existing containers and credentials"
    parameters = {
      PasswordParameter = {
        type              = "String"
        interpolationType = "ENV_VAR"
        allowedValues     = [for target in local.v1_exporter_targets : target.parameter]
      }
      ExpectedInstanceId = {
        type              = "String"
        interpolationType = "ENV_VAR"
        allowedValues     = [for target in local.v1_exporter_targets : target.id]
      }
      PrivateIp = {
        type              = "String"
        interpolationType = "ENV_VAR"
        allowedValues     = [for target in local.v1_exporter_targets : target.ip]
      }
    }
    mainSteps = [{
      action       = "aws:runShellScript"
      name         = "configureV1Exporters"
      precondition = { StringEquals = ["platformType", "Linux"] }
      inputs = {
        timeoutSeconds = "600"
        runCommand = [
          "set -eu",
          <<-PYTHON
          python3 - <<'PY'
          import base64, json, os, pathlib, subprocess, tempfile
          scripts = json.loads(${jsonencode(jsonencode(local.v1_exporter_scripts))})
          with tempfile.TemporaryDirectory(prefix='zipsai-v1-exporters-') as directory:
              for name, payload in scripts.items():
                  pathlib.Path(directory, name).write_bytes(base64.b64decode(payload))
              result = subprocess.run(['python3', directory + '/configure_v1_exporters.py'], env=os.environ.copy())
              raise SystemExit(result.returncode)
          PY
          PYTHON
        ]
      }
    }]
  })
  tags = { Project = "zipsai", ManagedBy = "Terraform" }
}

resource "aws_ssm_association" "v1_exporters" {
  for_each         = { for name, target in local.v1_exporter_targets : name => target if target.enabled }
  association_name = "zipsai-v1-${each.key}-exporters"
  name             = aws_ssm_document.v1_exporters.name
  document_version = aws_ssm_document.v1_exporters.latest_version
  parameters = {
    PasswordParameter  = each.value.parameter
    ExpectedInstanceId = each.value.id
    PrivateIp          = each.value.ip
  }
  targets {
    key    = "InstanceIds"
    values = [each.value.id]
  }
  wait_for_success_timeout_seconds = 600
}
