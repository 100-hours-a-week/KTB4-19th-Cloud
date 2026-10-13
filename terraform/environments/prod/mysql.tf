data "aws_security_group" "legacy_backend" {
  id = var.legacy_backend_security_group_id
}

module "mysql" {
  source = "../../modules/mysql"

  name_prefix    = local.name_prefix
  common_tags    = local.common_tags
  vpc_id         = data.terraform_remote_state.network.outputs.vpc_id
  vpc_cidr_block = data.terraform_remote_state.network.outputs.vpc_cidr_block

  ami_id        = var.mysql_ami_id
  instance_type = var.mysql_instance_type

  primary_subnet_id         = data.terraform_remote_state.network.outputs.private_data_subnet_ids.ap_northeast_2c
  primary_availability_zone = "ap-northeast-2c"
  replica_subnet_id         = data.terraform_remote_state.network.outputs.private_data_subnet_ids.ap_northeast_2a
  replica_availability_zone = "ap-northeast-2a"

  client_security_group_ids = {
    legacy_backend = data.aws_security_group.legacy_backend.id
    api_tasks      = aws_security_group.api_tasks.id
    worker_tasks   = aws_security_group.worker_tasks.id
  }

  monitoring_security_group_id = data.terraform_remote_state.network.outputs.monitoring_server_security_group_id
  data_volume_size_gib         = var.mysql_data_volume_size_gib
}
