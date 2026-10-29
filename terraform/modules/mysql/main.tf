locals {
  nodes = { for role, node in {
    primary = {
      availability_zone = var.primary_availability_zone
      subnet_id         = var.primary_subnet_id
      server_id         = 101
    }
    replica = {
      availability_zone = var.replica_availability_zone
      subnet_id         = var.replica_subnet_id
      server_id         = 102
    }
  } : role => node if role == "primary" || var.enable_replica }
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "mysql" {
  name               = "${var.name_prefix}-mysql-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.mysql.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "read_parameters" {
  name = "${var.name_prefix}-mysql-parameters-read"
  role = aws_iam_role.mysql.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ReadMySQLInitializationParameters"
      Effect   = "Allow"
      Action   = ["ssm:GetParameter"]
      Resource = sort(tolist(var.secret_parameter_arns))
    }]
  })
}

resource "aws_iam_instance_profile" "mysql" {
  name = "${var.name_prefix}-mysql-profile"
  role = aws_iam_role.mysql.name

  tags = var.common_tags
}

resource "aws_security_group" "mysql" {
  name        = "${var.name_prefix}-mysql-sg"
  description = "MySQL Primary and Replica access"
  vpc_id      = var.vpc_id

  revoke_rules_on_delete = true

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-mysql-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "clients" {
  for_each = var.client_security_group_ids

  security_group_id            = aws_security_group.mysql.id
  description                  = "MySQL from approved application security group"
  referenced_security_group_id = each.value
  from_port                    = 3306
  ip_protocol                  = "tcp"
  to_port                      = 3306

  tags = var.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "replication" {
  security_group_id            = aws_security_group.mysql.id
  description                  = "MySQL replication between database nodes"
  referenced_security_group_id = aws_security_group.mysql.id
  from_port                    = 3306
  ip_protocol                  = "tcp"
  to_port                      = 3306

  tags = var.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "node_exporter" {
  security_group_id            = aws_security_group.mysql.id
  description                  = "Node Exporter scrape from Prometheus"
  referenced_security_group_id = var.monitoring_security_group_id
  from_port                    = 9100
  ip_protocol                  = "tcp"
  to_port                      = 9100

  tags = var.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "mysql_exporter" {
  security_group_id            = aws_security_group.mysql.id
  description                  = "MySQL Exporter scrape from Prometheus"
  referenced_security_group_id = var.monitoring_security_group_id
  from_port                    = 9104
  ip_protocol                  = "tcp"
  to_port                      = 9104

  tags = var.common_tags
}

resource "aws_vpc_security_group_egress_rule" "replication" {
  security_group_id            = aws_security_group.mysql.id
  description                  = "MySQL replication between database nodes"
  referenced_security_group_id = aws_security_group.mysql.id
  from_port                    = 3306
  ip_protocol                  = "tcp"
  to_port                      = 3306

  tags = var.common_tags
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.mysql.id
  description       = "HTTPS to private AWS service endpoints"
  cidr_ipv4         = var.vpc_cidr_block
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443

  tags = var.common_tags
}

resource "aws_vpc_security_group_egress_rule" "dns_udp" {
  security_group_id = aws_security_group.mysql.id
  description       = "DNS over UDP inside the VPC"
  cidr_ipv4         = var.vpc_cidr_block
  from_port         = 53
  ip_protocol       = "udp"
  to_port           = 53

  tags = var.common_tags
}

resource "aws_vpc_security_group_egress_rule" "dns_tcp" {
  security_group_id = aws_security_group.mysql.id
  description       = "DNS over TCP inside the VPC"
  cidr_ipv4         = var.vpc_cidr_block
  from_port         = 53
  ip_protocol       = "tcp"
  to_port           = 53

  tags = var.common_tags
}

resource "aws_ebs_volume" "data" {
  for_each = local.nodes

  availability_zone = each.value.availability_zone
  encrypted         = true
  kms_key_id        = var.kms_key_id
  type              = "gp3"
  size              = var.data_volume_size_gib
  iops              = var.data_volume_iops
  throughput        = var.data_volume_throughput

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-mysql-${each.key}-data"
    Role = each.key
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_instance" "mysql" {
  for_each = local.nodes

  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = each.value.subnet_id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.mysql.id]
  iam_instance_profile        = aws_iam_instance_profile.mysql.name
  ebs_optimized               = true

  user_data = templatefile("${path.module}/templates/bootstrap.sh.tftpl", {
    data_volume_id = replace(aws_ebs_volume.data[each.key].id, "-", "")
    node_role      = each.key
    server_id      = each.value.server_id
  })

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted             = true
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gib
    delete_on_termination = true

    tags = merge(var.common_tags, {
      Name = "${var.name_prefix}-mysql-${each.key}-root"
      Role = each.key
    })
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-mysql-${each.key}"
    Role = each.key
  })
}

resource "aws_volume_attachment" "data" {
  for_each = local.nodes

  device_name                    = "/dev/sdf"
  instance_id                    = aws_instance.mysql[each.key].id
  volume_id                      = aws_ebs_volume.data[each.key].id
  stop_instance_before_detaching = true
}

