# Accounts/network only. GTID, replication channels, schema/data and application
# runtime are deliberately not changed by this preparation step.
variable "migration_source_instance_id" {
  description = "Existing production V1 MySQL host; never replaced by this root."
  type        = string
  default     = "i-06c0ca0d997f03792"
  validation {
    condition     = can(regex("^i-[0-9a-f]+$", var.migration_source_instance_id))
    error_message = "A valid existing EC2 instance ID is required."
  }
}

data "aws_instance" "migration_source" {
  instance_id = var.migration_source_instance_id
}

resource "aws_vpc_security_group_ingress_rule" "migration_source_from_mysql" {
  security_group_id            = data.aws_security_group.legacy_backend.id
  description                  = "Production MySQL nodes pull V1 migration binlogs"
  referenced_security_group_id = module.mysql.security_group_id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
  tags                         = merge(local.common_tags, { Name = "${local.name_prefix}-source-from-mysql" })
  lifecycle {
    precondition {
      condition     = contains(data.aws_instance.migration_source.vpc_security_group_ids, var.legacy_backend_security_group_id)
      error_message = "The migration source must have the reviewed legacy security group."
    }
  }
}

resource "aws_vpc_security_group_egress_rule" "mysql_to_migration_source" {
  security_group_id            = module.mysql.security_group_id
  description                  = "Production MySQL nodes pull V1 migration binlogs"
  referenced_security_group_id = data.aws_security_group.legacy_backend.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
  tags                         = merge(local.common_tags, { Name = "${local.name_prefix}-mysql-to-source" })
}

resource "aws_iam_role_policy" "migration_source_replication_secret" {
  name = "${local.name_prefix}-migration-source-replication-secret"
  role = var.legacy_ec2_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter"]
      Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/zipsai/prod/mysql-v1/replication-password"
    }]
  })
}

# The receiver must retrieve the source replication credential for authenticated
# preflight and the later (separately approved) CHANGE REPLICATION SOURCE step.
resource "aws_iam_role_policy" "mysql_source_replication_secret" {
  name = "${local.name_prefix}-mysql-source-replication-secret"
  role = module.mysql.iam_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter"]
      Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/zipsai/prod/mysql-v1/replication-password"
    }]
  })
}

locals {
  migration_account_plans = {
    source = {
      schema_version = 1
      instance_id    = data.aws_instance.migration_source.id
      server_id      = 1
      engine         = "docker"
      accounts = [{
        kind      = "replication"
        user      = "zipsai_repl"
        host      = module.mysql.private_ips.primary
        parameter = "/zipsai/prod/mysql-v1/replication-password"
      }]
    }
    primary = {
      schema_version = 1
      instance_id    = module.mysql.instance_ids.primary
      server_id      = 101
      engine         = "native"
      accounts = [
        {
          kind      = "app"
          user      = "zipsai_app"
          host      = "%"
          parameter = "/zipsai/prod/mysql-v2/password"
        },
        {
          kind      = "replication"
          user      = "zipsai_repl"
          host      = module.mysql.private_ips.replica
          parameter = "/zipsai/prod/mysql-v2/replication-password"
        }
      ]
    }
    replica = {
      schema_version = 1
      instance_id    = module.mysql.instance_ids.replica
      server_id      = 102
      engine         = "native"
      accounts = [{
        kind      = "app"
        user      = "zipsai_app"
        host      = "%"
        parameter = "/zipsai/prod/mysql-v2/password"
      }]
    }
  }
  migration_account_scripts = {
    "configure_mysql_exporter.py"     = base64encode(file("${path.module}/../../modules/mysql/scripts/configure_mysql_exporter.py"))
    "configure_migration_accounts.py" = base64encode(file("${path.module}/../../modules/mysql/scripts/configure_migration_accounts.py"))
  }
}

resource "aws_ssm_document" "migration_accounts" {
  name            = "${local.name_prefix}-migration-accounts"
  document_type   = "Command"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Prepare production migration accounts without rotating credentials or changing GTID/runtime"
    parameters = {
      AccountPlan = {
        type              = "String"
        interpolationType = "ENV_VAR"
        allowedValues     = [for plan in local.migration_account_plans : jsonencode(plan)]
      }
    }
    mainSteps = [{
      action       = "aws:runShellScript"
      name         = "prepareMigrationAccounts"
      precondition = { StringEquals = ["platformType", "Linux"] }
      inputs = {
        timeoutSeconds = "300"
        runCommand = [
          "set -eu",
          <<-PYTHON
          python3 - <<'PY'
          import base64, json, os, pathlib, subprocess, tempfile
          scripts = json.loads(${jsonencode(jsonencode(local.migration_account_scripts))})
          with tempfile.TemporaryDirectory(prefix='zipsai-migration-accounts-') as directory:
              os.chmod(directory, 0o700)
              for name, payload in scripts.items():
                  pathlib.Path(directory, name).write_bytes(base64.b64decode(payload))
              result = subprocess.run(['python3', directory + '/configure_migration_accounts.py'], env=os.environ.copy())
              raise SystemExit(result.returncode)
          PY
          PYTHON
        ]
      }
    }]
  })
  tags = local.common_tags
}

resource "aws_ssm_association" "migration_accounts" {
  for_each         = local.migration_account_plans
  association_name = "${local.name_prefix}-migration-accounts-${each.key}"
  name             = aws_ssm_document.migration_accounts.name
  document_version = aws_ssm_document.migration_accounts.latest_version
  parameters       = { AccountPlan = jsonencode(each.value) }
  targets {
    key    = "InstanceIds"
    values = [each.value.instance_id]
  }
  wait_for_success_timeout_seconds = 300
  depends_on                       = [aws_iam_role_policy.migration_source_replication_secret]
}
