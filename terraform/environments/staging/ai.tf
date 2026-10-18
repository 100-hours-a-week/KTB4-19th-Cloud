locals {
  ai_secret_parameters = {
    ai-api = merge({
      LLM_API_KEY          = "/zipsai/${local.environment}/ai/llm-api-key"
      QDRANT_ADMIN_API_KEY = "/zipsai/${local.environment}/ai/qdrant-admin-api-key"
      LANGFUSE_SECRET_KEY  = "/zipsai/${local.environment}/ai/langfuse/secret-key"
    }, var.ai_api_secret_parameter_names)
    embedding = merge({
      LANGFUSE_SECRET_KEY = "/zipsai/${local.environment}/ai/langfuse/secret-key"
    }, var.embedding_secret_parameter_names)
    qdrant = {
      QDRANT_ADMIN_API_KEY     = lookup(var.ai_api_secret_parameter_names, "QDRANT_ADMIN_API_KEY", "/zipsai/${local.environment}/ai/qdrant-admin-api-key")
      QDRANT_READ_ONLY_API_KEY = var.qdrant_read_only_parameter_name != null ? var.qdrant_read_only_parameter_name : "/zipsai/${local.environment}/ai/qdrant-read-only-api-key"
    }
  }
}

module "ai" {
  source                      = "../../modules/ai"
  name_prefix                 = local.name_prefix
  environment                 = local.environment
  common_tags                 = local.common_tags
  aws_region                  = var.aws_region
  vpc_id                      = data.terraform_remote_state.network.outputs.vpc_id
  subnet_id                   = data.terraform_remote_state.network.outputs.private_app_subnet_2c_id
  availability_zone           = "ap-northeast-2c"
  private_dns_zone_id         = data.terraform_remote_state.network.outputs.private_dns_zone_id
  ami_id                      = var.ai_ami_id
  uploads_bucket_name         = var.uploads_bucket_name
  instance_types              = var.ai_instance_types
  root_volume_sizes           = var.ai_root_volume_sizes
  qdrant_data_volume_size_gib = var.qdrant_data_volume_size_gib
  client_security_group_ids = {
    api_tasks    = aws_security_group.api_tasks.id
    worker_tasks = aws_security_group.worker_tasks.id
  }
  image_repository_urls = {
    ai-api    = data.terraform_remote_state.shared.outputs.ecr_repository_urls.ai_api
    embedding = data.terraform_remote_state.shared.outputs.ecr_repository_urls.embedding
  }
  image_repository_arns = {
    ai-api    = data.terraform_remote_state.shared.outputs.ecr_repository_arns.ai_api
    embedding = data.terraform_remote_state.shared.outputs.ecr_repository_arns.embedding
  }
  api_environment        = var.ai_api_environment
  embedding_environment  = var.embedding_environment
  secret_parameter_names = local.ai_secret_parameters
  runtime_parameter_names = {
    ai-api = merge({
      LANGFUSE_BASE_URL   = "/zipsai/${local.environment}/ai/langfuse/base-url"
      LANGFUSE_PUBLIC_KEY = "/zipsai/${local.environment}/ai/langfuse/public-key"
      LLM_MODEL           = "/zipsai/${local.environment}/ai/llm-model"
      LLM_BASE_URL        = "/zipsai/${local.environment}/ai/llm-base-url"
      VLM_MODEL           = "/zipsai/${local.environment}/ai/vlm-model"
    }, var.ai_api_runtime_parameter_names)
    embedding = merge({
      LANGFUSE_BASE_URL   = "/zipsai/${local.environment}/ai/langfuse/base-url"
      LANGFUSE_PUBLIC_KEY = "/zipsai/${local.environment}/ai/langfuse/public-key"
    }, var.embedding_runtime_parameter_names)
    qdrant = {}
  }
  kms_key_arns = var.ai_parameter_kms_key_arns
}

resource "aws_ssm_parameter" "ai_deployment_contract" {
  name  = "/zipsai/${local.environment}/ai/deployment-contract"
  type  = "String"
  value = jsonencode(module.ai.deployment_contract)
  tags  = local.common_tags
}

output "ai_deployment" {
  value = {
    api_url            = module.ai.api_url
    contract_parameter = aws_ssm_parameter.ai_deployment_contract.name
    services           = module.ai.deployment_contract
  }
}
