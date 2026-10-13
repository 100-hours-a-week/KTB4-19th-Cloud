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

resource "aws_appconfig_deployment" "baseline" {
  application_id           = aws_appconfig_application.this.id
  environment_id           = aws_appconfig_environment.this.environment_id
  configuration_profile_id = aws_appconfig_configuration_profile.database_migration.configuration_profile_id
  configuration_version    = aws_appconfig_hosted_configuration_version.baseline.version_number
  deployment_strategy_id   = "AppConfig.AllAtOnce"
  description              = "Initial safe V1 writer configuration."

  tags = var.common_tags
}
