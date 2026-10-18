output "api_url" { value = "http://${local.dns_names["ai-api"]}:8000" }
output "deployment_contract" {
  value = {
    for name in keys(local.hosts) : name => {
      instance_id        = aws_instance.host[name].id
      private_dns        = local.dns_names[name]
      port               = local.hosts[name].port
      runtime_parameter  = aws_ssm_parameter.runtime[name].name
      runtime_parameters = var.runtime_parameter_names[name]
      secret_parameters  = var.secret_parameter_names[name]
      log_group          = aws_cloudwatch_log_group.host[name].name
      deploy_command     = name == "qdrant" ? "/opt/zipsai/deploy.sh" : "/opt/zipsai/deploy.sh <SHA7>"
      ssm_document       = aws_ssm_document.deploy[name].name
    }
  }
}
