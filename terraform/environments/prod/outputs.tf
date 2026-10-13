output "frontend_bucket_name" {
  description = "Production private Frontend origin bucket name."
  value       = module.frontend.bucket_name
}

output "frontend_cloudfront_distribution_id" {
  description = "Production CloudFront distribution ID."
  value       = module.frontend.distribution_id
}

output "frontend_cloudfront_domain_name" {
  description = "Production CloudFront domain available before DNS cutover."
  value       = module.frontend.distribution_domain_name
}

output "mysql_instance_ids" {
  description = "Production MySQL EC2 instance IDs keyed by role."
  value       = module.mysql.instance_ids
}

output "mysql_private_ips" {
  description = "Production MySQL private IP addresses keyed by role."
  value       = module.mysql.private_ips
}

output "mysql_data_volume_ids" {
  description = "Production MySQL EBS data volume IDs keyed by role."
  value       = module.mysql.data_volume_ids
}

output "mysql_security_group_id" {
  description = "Security group used by the Production MySQL nodes."
  value       = module.mysql.security_group_id
}

output "ecs_cluster_arn" {
  description = "Production ECS cluster ARN."
  value       = module.ecs.cluster_arn
}

output "ecs_api_service_name" {
  description = "Production ECS API service name."
  value       = module.ecs.api_service_name
}

output "ecs_worker_service_name" {
  description = "Production ECS Worker service name."
  value       = module.ecs.worker_service_name
}

output "api_alb_dns_name" {
  description = "Production API ALB DNS name used before DNS cutover."
  value       = module.ecs.alb_dns_name
}

output "api_alb_zone_id" {
  description = "Production API ALB Route 53 zone ID."
  value       = module.ecs.alb_zone_id
}

output "document_jobs_queue_url" {
  description = "Production document jobs queue URL."
  value       = module.document_jobs.queue_url
}

output "document_jobs_queue_arn" {
  description = "Production document jobs queue ARN."
  value       = module.document_jobs.queue_arn
}

output "document_jobs_dlq_url" {
  description = "Production document jobs DLQ URL."
  value       = module.document_jobs.dlq_url
}

output "document_jobs_dlq_alarm_arn" {
  description = "Production DLQ visible-message alarm ARN."
  value       = module.document_jobs.dlq_alarm_arn
}

output "api_tasks_security_group_id" {
  description = "Security group reserved for Production ECS API tasks."
  value       = aws_security_group.api_tasks.id
}

output "worker_tasks_security_group_id" {
  description = "Security group reserved for Production ECS Worker tasks."
  value       = aws_security_group.worker_tasks.id
}

output "valkey_endpoint_address" {
  description = "Production Valkey primary endpoint address."
  value       = module.valkey.endpoint_address
}

output "valkey_endpoint_port" {
  description = "Production Valkey primary endpoint port."
  value       = module.valkey.endpoint_port
}

output "valkey_username" {
  description = "Production Valkey RBAC username."
  value       = module.valkey.username
}

output "valkey_password_parameter_arn" {
  description = "Production Valkey password SSM parameter ARN."
  value       = module.valkey.password_parameter_arn
}

output "appconfig_runtime_configuration" {
  description = "Production AppConfig identifiers used by the Agent endpoint."
  value = {
    application = module.appconfig.application_name
    environment = module.appconfig.environment_name
    profile     = module.appconfig.configuration_profile_name
  }
}
