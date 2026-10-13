module "appconfig" {
  source = "../../modules/appconfig"

  name_prefix = local.name_prefix
  environment = local.environment
  common_tags = local.common_tags
}
