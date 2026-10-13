output "application_name" {
  description = "AppConfig application name used by the Agent endpoint."
  value       = aws_appconfig_application.this.name
}

output "environment_name" {
  description = "AppConfig environment name used by the Agent endpoint."
  value       = aws_appconfig_environment.this.name
}

output "configuration_profile_name" {
  description = "AppConfig configuration profile name used by the Agent endpoint."
  value       = aws_appconfig_configuration_profile.database_migration.name
}

output "configuration_arn" {
  description = "Data-plane configuration ARN granted to AppConfig Agent callers."
  value       = "arn:aws:appconfig:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:application/${aws_appconfig_application.this.id}/environment/${aws_appconfig_environment.this.environment_id}/configuration/${aws_appconfig_configuration_profile.database_migration.configuration_profile_id}"
}

output "baseline_deployment_state" {
  description = "State of the initial safe AppConfig deployment."
  value       = aws_appconfig_deployment.baseline.state
}
