module "appconfig" {
  source = "../../modules/appconfig"

  name_prefix = local.name_prefix
  environment = local.environment
  common_tags = local.common_tags
}

resource "aws_appconfig_deployment_strategy" "migration_rehearsal" {
  name                           = "${local.name_prefix}-migration-five-minute"
  description                    = "Immediate Staging migration configuration rollout with five minutes of observation."
  deployment_duration_in_minutes = 0
  final_bake_time_in_minutes     = 5
  growth_factor                  = 100
  growth_type                    = "LINEAR"
  replicate_to                   = "NONE"

  tags = local.common_tags
}

output "migration_rehearsal_deployment_strategy" {
  description = "Deployment strategy used by the Staging migration control script."
  value = {
    id   = aws_appconfig_deployment_strategy.migration_rehearsal.id
    name = aws_appconfig_deployment_strategy.migration_rehearsal.name
  }
}
