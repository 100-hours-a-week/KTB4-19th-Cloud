data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  profile_name = "database-migration"

  initial_configuration = {
    writer               = "V1"
    shadowReadPercent    = 0
    v2ReadPercent        = 0
    forwardWorkerEnabled = false
    reverseWorkerEnabled = false
  }

  configuration_schema = {
    "$schema" = "http://json-schema.org/draft-04/schema#"
    type      = "object"
    required = [
      "writer",
      "shadowReadPercent",
      "v2ReadPercent",
      "forwardWorkerEnabled",
      "reverseWorkerEnabled",
    ]
    additionalProperties = false
    properties = {
      writer = {
        type = "string"
        enum = ["V1", "V2"]
      }
      shadowReadPercent = {
        type    = "integer"
        minimum = 0
        maximum = 100
      }
      v2ReadPercent = {
        type    = "integer"
        minimum = 0
        maximum = 100
      }
      forwardWorkerEnabled = {
        type = "boolean"
      }
      reverseWorkerEnabled = {
        type = "boolean"
      }
    }
    not = {
      required = ["forwardWorkerEnabled", "reverseWorkerEnabled"]
      properties = {
        forwardWorkerEnabled = {
          enum = [true]
        }
        reverseWorkerEnabled = {
          enum = [true]
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
