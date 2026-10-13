module "valkey" {
  source = "../../modules/valkey"

  name_prefix = local.name_prefix
  common_tags = local.common_tags
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id
  subnet_ids  = values(data.terraform_remote_state.network.outputs.private_data_subnet_ids)

  client_security_group_ids = {
    api_tasks    = aws_security_group.api_tasks.id
    worker_tasks = aws_security_group.worker_tasks.id
  }

  password             = var.valkey_password
  password_version     = var.valkey_password_version
  ssm_parameter_name   = "/zipsai/${local.environment}/valkey/password"
  major_engine_version = "8"
}
