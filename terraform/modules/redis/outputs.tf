output "endpoint_address" {
  value = local.endpoint
}
output "endpoint_port" { value = 6379 }
output "username_parameter_arn" { value = aws_ssm_parameter.username.arn }
output "password_parameter_arn" { value = local.password_parameter_arn }
output "instance_id" { value = aws_instance.redis.id }
output "private_ip" { value = aws_instance.redis.private_ip }
output "security_group_id" { value = aws_security_group.redis.id }
