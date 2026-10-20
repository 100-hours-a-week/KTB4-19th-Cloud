output "cluster_arn" {
  description = "ECS cluster ARN."
  value       = aws_ecs_cluster.this.arn
}

output "deployment_contract_parameter_name" {
  description = "SSM parameter containing infrastructure inputs for Backend CD."
  value       = aws_ssm_parameter.deployment_contract.name
}

output "api_service_name" {
  description = "API ECS service name."
  value       = aws_ecs_service.api.name
}

output "worker_service_name" {
  description = "Worker ECS service name."
  value       = aws_ecs_service.worker.name
}

output "alb_arn" {
  description = "API Application Load Balancer ARN."
  value       = aws_lb.api.arn
}

output "https_listener_arn" {
  description = "HTTPS listener ARN, when HTTPS is enabled."
  value       = try(aws_lb_listener.https[0].arn, null)
}

output "alb_dns_name" {
  description = "API Application Load Balancer DNS name."
  value       = aws_lb.api.dns_name
}

output "alb_zone_id" {
  description = "API Application Load Balancer Route 53 zone ID."
  value       = aws_lb.api.zone_id
}

output "api_target_group_arn" {
  description = "API target group ARN."
  value       = aws_lb_target_group.api.arn
}
