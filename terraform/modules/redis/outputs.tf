output "endpoint_address" {
  value = local.endpoint
}
output "endpoint_port" { value = 6379 }
output "username_parameter_arn" { value = aws_ssm_parameter.username.arn }
output "password_parameter_arn" { value = local.password_parameter_arn }
output "instance_id" { value = try(aws_instance.redis[0].id, null) }
output "private_ip" { value = try(aws_instance.redis[0].private_ip, null) }
output "security_group_id" { value = try(aws_security_group.redis[0].id, null) }
