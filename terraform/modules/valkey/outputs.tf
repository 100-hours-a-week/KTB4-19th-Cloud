output "endpoint_address" {
  description = "Valkey primary endpoint address."
  value       = aws_elasticache_serverless_cache.this.endpoint[0].address
}

output "endpoint_port" {
  description = "Valkey primary endpoint port."
  value       = aws_elasticache_serverless_cache.this.endpoint[0].port
}

output "username" {
  description = "Valkey RBAC application username."
  value       = local.username
}

output "security_group_id" {
  description = "Security group attached to the Valkey serverless endpoint."
  value       = aws_security_group.valkey.id
}

output "user_group_id" {
  description = "Valkey RBAC user group ID."
  value       = aws_elasticache_user_group.application.user_group_id
}

output "password_parameter_arn" {
  description = "ARN of the SSM SecureString containing the Valkey password."
  value       = aws_ssm_parameter.password.arn
}
