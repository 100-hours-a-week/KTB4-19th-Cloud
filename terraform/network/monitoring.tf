resource "aws_route53_zone" "private" {
  name = "zipsai.internal"

  vpc {
    vpc_id = aws_vpc.zipsai.id
  }

  tags = merge(var.shared_tags, {
    Name = "zipsai.internal"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_security_group" "monitoring_clients" {
  name        = "zipsai-shared-monitoring-clients-sg"
  description = "Clients allowed to send logs to the private monitoring stack"
  vpc_id      = aws_vpc.zipsai.id

  revoke_rules_on_delete = true

  tags = merge(var.shared_tags, {
    Name = "zipsai-shared-monitoring-clients-sg"
  })
}

resource "aws_security_group" "monitoring_server" {
  name        = "zipsai-shared-monitoring-server-sg"
  description = "Private Prometheus, Loki, and Grafana server"
  vpc_id      = aws_vpc.zipsai.id

  revoke_rules_on_delete = true

  tags = merge(var.shared_tags, {
    Name = "zipsai-shared-monitoring-server-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "monitoring_loki_from_clients" {
  security_group_id            = aws_security_group.monitoring_server.id
  description                  = "Loki ingestion from approved ECS tasks"
  referenced_security_group_id = aws_security_group.monitoring_clients.id
  from_port                    = 3100
  ip_protocol                  = "tcp"
  to_port                      = 3100

  tags = var.shared_tags
}

resource "aws_vpc_security_group_egress_rule" "monitoring_clients_to_loki" {
  security_group_id            = aws_security_group.monitoring_clients.id
  description                  = "Send container logs to private Loki"
  referenced_security_group_id = aws_security_group.monitoring_server.id
  from_port                    = 3100
  ip_protocol                  = "tcp"
  to_port                      = 3100

  tags = var.shared_tags
}

resource "aws_vpc_security_group_egress_rule" "monitoring_http" {
  security_group_id = aws_security_group.monitoring_server.id
  description       = "Package and container image downloads through NAT"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80

  tags = var.shared_tags
}

resource "aws_vpc_security_group_egress_rule" "monitoring_https" {
  security_group_id = aws_security_group.monitoring_server.id
  description       = "AWS APIs and container registries through NAT"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443

  tags = var.shared_tags
}

resource "aws_vpc_security_group_egress_rule" "monitoring_dns_udp" {
  security_group_id = aws_security_group.monitoring_server.id
  description       = "DNS inside the VPC"
  cidr_ipv4         = aws_vpc.zipsai.cidr_block
  from_port         = 53
  ip_protocol       = "udp"
  to_port           = 53

  tags = var.shared_tags
}

resource "aws_vpc_security_group_egress_rule" "monitoring_dns_tcp" {
  security_group_id = aws_security_group.monitoring_server.id
  description       = "DNS fallback inside the VPC"
  cidr_ipv4         = aws_vpc.zipsai.cidr_block
  from_port         = 53
  ip_protocol       = "tcp"
  to_port           = 53

  tags = var.shared_tags
}

resource "aws_vpc_security_group_egress_rule" "monitoring_backend_metrics" {
  security_group_id = aws_security_group.monitoring_server.id
  description       = "Prometheus scrape of Backend metrics"
  cidr_ipv4         = aws_vpc.zipsai.cidr_block
  from_port         = 8080
  ip_protocol       = "tcp"
  to_port           = 8080

  tags = var.shared_tags
}

resource "aws_vpc_security_group_egress_rule" "monitoring_node_exporters" {
  security_group_id = aws_security_group.monitoring_server.id
  description       = "Prometheus scrape of database host metrics"
  cidr_ipv4         = aws_vpc.zipsai.cidr_block
  from_port         = 9100
  ip_protocol       = "tcp"
  to_port           = 9100

  tags = var.shared_tags
}

resource "aws_vpc_security_group_egress_rule" "monitoring_mysql_exporters" {
  security_group_id = aws_security_group.monitoring_server.id
  description       = "Prometheus scrape of MySQL metrics"
  cidr_ipv4         = aws_vpc.zipsai.cidr_block
  from_port         = 9104
  ip_protocol       = "tcp"
  to_port           = 9104

  tags = var.shared_tags
}

resource "aws_vpc_security_group_ingress_rule" "legacy_node_exporter_from_monitoring" {
  security_group_id            = var.legacy_service_security_group_id
  description                  = "V1 host metrics from the private monitoring server"
  referenced_security_group_id = aws_security_group.monitoring_server.id
  from_port                    = 9100
  ip_protocol                  = "tcp"
  to_port                      = 9100

  tags = var.shared_tags
}

resource "aws_vpc_security_group_ingress_rule" "legacy_mysql_exporter_from_monitoring" {
  security_group_id            = var.legacy_service_security_group_id
  description                  = "V1 MySQL metrics from the private monitoring server"
  referenced_security_group_id = aws_security_group.monitoring_server.id
  from_port                    = 9104
  ip_protocol                  = "tcp"
  to_port                      = 9104

  tags = var.shared_tags
}
