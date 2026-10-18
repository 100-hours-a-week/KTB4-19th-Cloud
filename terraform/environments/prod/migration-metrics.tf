# V1 private application metrics only; no public CIDR and no runtime deployment.
resource "aws_vpc_security_group_ingress_rule" "migration_application_metrics" {
  security_group_id            = data.aws_security_group.legacy_backend.id
  description                  = "Production migration API and Worker metrics from monitoring"
  referenced_security_group_id = data.terraform_remote_state.network.outputs.monitoring_server_security_group_id
  from_port                    = 8080
  to_port                      = 8081
  ip_protocol                  = "tcp"
  tags                         = merge(local.common_tags, { Name = "${local.name_prefix}-migration-app-metrics" })
}
