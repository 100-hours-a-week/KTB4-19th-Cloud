data "aws_subnet" "selected" {
  id = var.subnet_id
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "monitoring" {
  name               = "${var.name_prefix}-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "grafana_password" {
  statement {
    actions = ["ssm:GetParameter"]
    resources = [
      "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.grafana_admin_password_parameter_name}",
    ]
  }
}

resource "aws_iam_role_policy" "grafana_password" {
  name   = "${var.name_prefix}-grafana-password"
  role   = aws_iam_role.monitoring.id
  policy = data.aws_iam_policy_document.grafana_password.json
}

resource "aws_iam_instance_profile" "monitoring" {
  name = "${var.name_prefix}-profile"
  role = aws_iam_role.monitoring.name

  tags = var.common_tags
}

resource "aws_ebs_volume" "data" {
  availability_zone = data.aws_subnet.selected.availability_zone
  encrypted         = true
  type              = "gp3"
  size              = var.data_volume_size_gib
  iops              = 3000
  throughput        = 125

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-data"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_instance" "monitoring" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  associate_public_ip_address = false
  vpc_security_group_ids      = [var.security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.monitoring.name
  ebs_optimized               = true

  user_data = templatefile("${path.module}/templates/bootstrap.sh.tftpl", {
    aws_region                      = var.aws_region
    data_volume_id                  = replace(aws_ebs_volume.data.id, "-", "")
    grafana_password_parameter_name = var.grafana_admin_password_parameter_name
    compose_config_gzip_base64      = var.compose_config_gzip_base64
    prometheus_config_gzip_base64   = var.prometheus_config_gzip_base64
    loki_config_gzip_base64         = var.loki_config_gzip_base64
    grafana_datasources_gzip_base64 = var.grafana_datasources_gzip_base64
  })
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted             = true
    volume_type           = "gp3"
    volume_size           = 16
    delete_on_termination = true
  }

  tags = merge(var.common_tags, {
    Name = var.name_prefix
  })

  volume_tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-root"
  })
}

resource "aws_volume_attachment" "data" {
  device_name                    = "/dev/sdf"
  instance_id                    = aws_instance.monitoring.id
  volume_id                      = aws_ebs_volume.data.id
  stop_instance_before_detaching = true
}

resource "aws_route53_record" "monitoring" {
  zone_id = var.private_dns_zone_id
  name    = "monitoring.zipsai.internal"
  type    = "A"
  ttl     = 30
  records = [aws_instance.monitoring.private_ip]
}

resource "aws_route53_record" "loki" {
  zone_id = var.private_dns_zone_id
  name    = "loki.monitoring.zipsai.internal"
  type    = "A"
  ttl     = 30
  records = [aws_instance.monitoring.private_ip]
}
