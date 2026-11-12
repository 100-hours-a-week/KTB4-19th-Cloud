output "cluster_arn" {
  description = "ECS cluster ARN."
  value       = try(aws_ecs_cluster.this[0].arn, null)
}

output "deployment_contract_parameter_name" {
  description = "SSM parameter containing infrastructure inputs for Backend CD."
  value       = try(aws_ssm_parameter.deployment_contract[0].name, null)
}

output "api_service_name" {
  description = "API ECS service name."
  value       = try(aws_ecs_service.api[0].name, null)
}

output "worker_service_name" {
  description = "Worker ECS service name."
  value       = try(aws_ecs_service.worker[0].name, null)
}

output "alb_arn" {
  description = "API Application Load Balancer ARN."
  value       = try(aws_lb.api[0].arn, null)
}

output "https_listener_arn" {
  description = "HTTPS listener ARN, when HTTPS is enabled."
  value       = try(aws_lb_listener.https[0].arn, null)
}

output "alb_dns_name" {
  description = "API Application Load Balancer DNS name."
  value       = try(aws_lb.api[0].dns_name, null)
}

output "alb_zone_id" {
  description = "API Application Load Balancer Route 53 zone ID."
  value       = try(aws_lb.api[0].zone_id, null)
}

output "api_target_group_arn" {
  description = "API target group ARN."
  value       = try(aws_lb_target_group.api[0].arn, null)
}
