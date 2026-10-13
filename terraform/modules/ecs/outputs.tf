output "cluster_arn" {
  description = "ECS cluster ARN."
  value       = aws_ecs_cluster.this.arn
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
