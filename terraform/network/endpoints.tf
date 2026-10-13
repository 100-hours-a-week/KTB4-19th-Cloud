locals {
  ssm_interface_endpoint_services = toset([
    "ssm",
    "ssmmessages",
  ])
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.zipsai.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = [
    aws_route_table.private_app.id,
    aws_route_table.private_data.id,
  ]

  tags = merge(var.shared_tags, {
    Name = "zipsai-shared-s3-endpoint"
  })
}

resource "aws_security_group" "ssm_endpoints" {
  name        = "zipsai-shared-ssm-endpoints-sg"
  description = "Allow HTTPS from private data subnets to SSM interface endpoints"
  vpc_id      = aws_vpc.zipsai.id

  tags = merge(var.shared_tags, {
    Name = "zipsai-shared-ssm-endpoints-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "ssm_https_data_2c" {
  security_group_id = aws_security_group.ssm_endpoints.id
  description       = "HTTPS from private data subnet in ap-northeast-2c"
  cidr_ipv4         = aws_subnet.private_data_2c.cidr_block
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443

  tags = var.shared_tags
}

resource "aws_vpc_security_group_ingress_rule" "ssm_https_data_2a" {
  security_group_id = aws_security_group.ssm_endpoints.id
  description       = "HTTPS from private data subnet in ap-northeast-2a"
  cidr_ipv4         = aws_subnet.private_data_2a.cidr_block
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443

  tags = var.shared_tags
}

resource "aws_vpc_security_group_ingress_rule" "ssm_https_monitoring" {
  security_group_id            = aws_security_group.ssm_endpoints.id
  description                  = "HTTPS from the private monitoring server"
  referenced_security_group_id = aws_security_group.monitoring_server.id
  from_port                    = 443
  ip_protocol                  = "tcp"
  to_port                      = 443

  tags = var.shared_tags
}

resource "aws_vpc_endpoint" "ssm" {
  for_each = local.ssm_interface_endpoint_services

  vpc_id              = aws_vpc.zipsai.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids = [
    aws_subnet.private_data_2c.id,
  ]
  security_group_ids = [aws_security_group.ssm_endpoints.id]

  tags = merge(var.shared_tags, {
    Name = "zipsai-shared-${each.value}-endpoint"
  })
}
