output "redis_connection" {
  description = "Private Redis DNS and runtime parameter paths. Does not contain passwords."
  value = {
    host                      = module.redis.endpoint_address
    port                      = module.redis.endpoint_port
    instance_id               = module.redis.instance_id
    private_ip                = module.redis.private_ip
    username_parameter_arn    = module.redis.username_parameter_arn
    password_parameter_arn    = module.redis.password_parameter_arn
    api_runtime_parameters    = { for name, parameter in aws_ssm_parameter.api_runtime : name => parameter.name }
    worker_runtime_parameters = { for name, parameter in aws_ssm_parameter.worker_runtime : name => parameter.name }
  }
}
