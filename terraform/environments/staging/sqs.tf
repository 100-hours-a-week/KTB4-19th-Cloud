module "document_jobs" {
  source = "../../modules/sqs"

  name_prefix = local.name_prefix
  common_tags = local.common_tags
}

