output "frontend_bucket_name" {
  description = "Staging private Frontend origin bucket name."
  value       = module.frontend.bucket_name
}

output "frontend_cloudfront_distribution_id" {
  description = "Staging CloudFront distribution ID."
  value       = module.frontend.distribution_id
}

output "frontend_cloudfront_domain_name" {
  description = "Staging CloudFront domain available before Route 53 delegation."
  value       = module.frontend.distribution_domain_name
}

output "uploads_bucket_name" {
  description = "Staging private upload bucket name."
  value       = aws_s3_bucket.uploads.id
}

output "mysql_instance_ids" {
  description = "Staging MySQL EC2 instance IDs keyed by role."
  value       = module.mysql.instance_ids
}

output "mysql_private_ips" {
  description = "Staging MySQL private IP addresses keyed by role."
  value       = module.mysql.private_ips
}

output "mysql_data_volume_ids" {
  description = "Staging MySQL data EBS volume IDs keyed by role."
  value       = module.mysql.data_volume_ids
}

output "mysql_security_group_id" {
  description = "Security group used by the Staging MySQL nodes."
  value       = module.mysql.security_group_id
}

output "ecs_cluster_arn" {
  description = "Staging ECS cluster ARN."
  value       = module.ecs.cluster_arn
}

output "ecs_api_service_name" {
  description = "Staging ECS API service name."
  value       = module.ecs.api_service_name
}

output "ecs_worker_service_name" {
  description = "Staging ECS Worker service name."
  value       = module.ecs.worker_service_name
}

output "api_alb_dns_name" {
  description = "Staging API ALB DNS name used before DNS cutover."
  value       = module.ecs.alb_dns_name
}

output "api_alb_zone_id" {
  description = "Staging API ALB Route 53 zone ID."
  value       = module.ecs.alb_zone_id
}

output "api_tasks_security_group_id" {
  description = "Security group reserved for Staging ECS API tasks."
  value       = aws_security_group.api_tasks.id
}

output "worker_tasks_security_group_id" {
  description = "Security group reserved for Staging ECS Worker tasks."
  value       = aws_security_group.worker_tasks.id
}

output "appconfig_runtime_configuration" {
  description = "Staging AppConfig identifiers used by the Agent endpoint."
  value = {
    application = module.appconfig.application_name
    environment = module.appconfig.environment_name
    profile     = module.appconfig.configuration_profile_name
    versions    = module.appconfig.configuration_versions
  }
}
