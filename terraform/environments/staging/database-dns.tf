resource "aws_route53_record" "mysql_primary" {
  zone_id = data.terraform_remote_state.network.outputs.private_dns_zone_id
  name    = "mysql-primary.${local.environment}.zipsai.internal"
  type    = "A"
  ttl     = 30
  records = [module.mysql.private_ips.primary]
}

