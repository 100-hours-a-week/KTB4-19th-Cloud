data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  profile_name = "database-migration"

  initial_configuration = {
    migration = {
      mode                 = "V1_PRIMARY"
      switchAt             = null
      workerMode           = "PAUSED"
      forwardWorkerEnabled = false
      reverseWorkerEnabled = false
      v2ReadPercent        = 0
      shadowReadPercent    = 0
    }
  }

  reusable_configurations = {
    "forward-worker-running-v1" = {
      description = "Run only the V1 to V2 Outbox Worker while reads remain on V1."
      migration = merge(local.initial_configuration.migration, {
        workerMode           = "RUNNING"
        forwardWorkerEnabled = true
      })
    }
    "shadow-read-10-v1" = {
      description = "Compare 10 percent of V1 reads with V2 while responses remain on V1."
      migration = merge(local.initial_configuration.migration, {
        workerMode           = "RUNNING"
        forwardWorkerEnabled = true
        shadowReadPercent    = 10
      })
    }
    "shadow-read-100-v1" = {
      description = "Compare all V1 reads with V2 while responses remain on V1."
      migration = merge(local.initial_configuration.migration, {
        workerMode           = "RUNNING"
        forwardWorkerEnabled = true
        shadowReadPercent    = 100
      })
    }
    "v2-read-10-v1" = {
      description = "Serve 10 percent of reads from V2 after full shadow-read validation."
      migration = merge(local.initial_configuration.migration, {
        workerMode           = "RUNNING"
        forwardWorkerEnabled = true
        v2ReadPercent        = 10
        shadowReadPercent    = 100
      })
    }
    "v2-read-50-v1" = {
      description = "Serve 50 percent of reads from V2 after full shadow-read validation."
      migration = merge(local.initial_configuration.migration, {
        workerMode           = "RUNNING"
        forwardWorkerEnabled = true
        v2ReadPercent        = 50
        shadowReadPercent    = 100
      })
    }
    "v2-read-100-v1" = {
      description = "Serve all reads from V2 while V1 remains the writer."
      migration = merge(local.initial_configuration.migration, {
        workerMode           = "RUNNING"
        forwardWorkerEnabled = true
        v2ReadPercent        = 100
        shadowReadPercent    = 100
      })
    }
    "drain-workers-v2" = {
      description = "Drain in-flight migration work while V2 remains the primary database."
      migration = merge(local.initial_configuration.migration, {
        mode                 = "V2_PRIMARY"
        workerMode           = "DRAINING"
        forwardWorkerEnabled = true
        reverseWorkerEnabled = true
        v2ReadPercent        = 100
        shadowReadPercent    = 100
      })
    }
    "complete-migration-v2" = {
      description = "Pause migration workers after V2 becomes the stable primary database."
      migration = merge(local.initial_configuration.migration, {
        mode              = "V2_PRIMARY"
        workerMode        = "PAUSED"
        v2ReadPercent     = 100
        shadowReadPercent = 0
      })
    }
  }

  configuration_schema = {
    "$schema"            = "http://json-schema.org/draft-04/schema#"
    type                 = "object"
    required             = ["migration"]
    additionalProperties = false
    properties = {
      migration = {
        type = "object"
        required = [
          "mode",
          "switchAt",
          "workerMode",
          "forwardWorkerEnabled",
          "reverseWorkerEnabled",
          "v2ReadPercent",
          "shadowReadPercent",
        ]
        additionalProperties = false
        properties = {
          mode = {
            type = "string"
            enum = ["V1_PRIMARY", "V2_PRIMARY"]
          }
          switchAt = {
            type   = ["string", "null"]
            format = "date-time"
          }
          workerMode = {
            type = "string"
            enum = ["PAUSED", "RUNNING", "DRAINING"]
          }
          forwardWorkerEnabled = {
            type = "boolean"
          }
          reverseWorkerEnabled = {
            type = "boolean"
          }
          v2ReadPercent = {
            type    = "integer"
            minimum = 0
            maximum = 100
          }
          shadowReadPercent = {
            type    = "integer"
            minimum = 0
            maximum = 100
          }
        }
      }
    }
  }
}

resource "aws_appconfig_application" "this" {
  name        = var.name_prefix
  description = "Runtime configuration for ${var.name_prefix}."

  tags = var.common_tags
}

resource "aws_appconfig_environment" "this" {
  application_id = aws_appconfig_application.this.id
  name           = var.environment
  description    = "${var.environment} runtime configuration."

  tags = var.common_tags
}

resource "aws_appconfig_configuration_profile" "database_migration" {
  application_id = aws_appconfig_application.this.id
  name           = local.profile_name
  description    = "Database migration writer, read routing, and Outbox Worker controls."
  location_uri   = "hosted"
  type           = "AWS.Freeform"

  validator {
    type    = "JSON_SCHEMA"
    content = jsonencode(local.configuration_schema)
  }

  tags = var.common_tags
}

resource "aws_appconfig_hosted_configuration_version" "baseline" {
  application_id           = aws_appconfig_application.this.id
  configuration_profile_id = aws_appconfig_configuration_profile.database_migration.configuration_profile_id
  description              = "Safe baseline before database migration starts."
  content_type             = "application/json"
  content                  = jsonencode(local.initial_configuration)
}

resource "aws_appconfig_hosted_configuration_version" "reusable" {
  for_each = local.reusable_configurations

  application_id           = aws_appconfig_application.this.id
  configuration_profile_id = aws_appconfig_configuration_profile.database_migration.configuration_profile_id
  description              = each.value.description
  content_type             = "application/json"
  content = jsonencode({
    migration = each.value.migration
  })
  version_label = each.key
}

resource "aws_appconfig_deployment" "baseline" {
  application_id           = aws_appconfig_application.this.id
  environment_id           = aws_appconfig_environment.this.environment_id
  configuration_profile_id = aws_appconfig_configuration_profile.database_migration.configuration_profile_id
  configuration_version    = aws_appconfig_hosted_configuration_version.baseline.version_number
  deployment_strategy_id   = "AppConfig.AllAtOnce"
  description              = "Initial safe V1 writer configuration."

  tags = var.common_tags
}
