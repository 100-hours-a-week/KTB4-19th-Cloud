resource "aws_appconfig_deployment_strategy" "migration_production" {
  name                           = "${local.name_prefix}-migration-three-minute"
  description                    = "Immediate production migration configuration rollout with three minutes of observation."
  deployment_duration_in_minutes = 0
  final_bake_time_in_minutes     = 3
  growth_factor                  = 100
  growth_type                    = "LINEAR"
  replicate_to                   = "NONE"

  tags = local.common_tags
}
