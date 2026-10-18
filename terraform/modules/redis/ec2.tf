data "aws_ami" "redis" {
  owners = ["099720109477"]
  filter {
    name   = "image-id"
    values = [var.ami_id]
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  endpoint                = "redis.services.${var.environment}.zipsai.internal"
  username_parameter_name = "/zipsai/${var.environment}/redis/username"
  password_parameter_name = "/zipsai/${var.environment}/redis/password"
  password_parameter_arn  = "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.password_parameter_name}"
}

resource "aws_ssm_parameter" "username" {
  name  = local.username_parameter_name
  type  = "String"
  value = var.username == "" ? "default" : var.username
  tags  = var.common_tags
  lifecycle { ignore_changes = [value] }
}

resource "aws_security_group" "redis" {
  name        = "${var.name_prefix}-redis-sg"
  description = "Private Redis access from approved API and Worker tasks"
  vpc_id      = var.vpc_id
  tags        = var.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "clients" {
  for_each                     = var.client_security_group_ids
  security_group_id            = aws_security_group.redis.id
  referenced_security_group_id = each.value
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
  tags                         = var.common_tags
}

resource "aws_vpc_security_group_egress_rule" "outbound" {
  security_group_id = aws_security_group.redis.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Package and image downloads, SSM and CloudWatch through App subnet NAT"
  tags              = var.common_tags
}

resource "aws_cloudwatch_log_group" "redis" {
  name              = "/zipsai/${var.environment}/redis"
  retention_in_days = 14
  tags              = var.common_tags
}

resource "aws_iam_role" "instance" {
  name = "${var.name_prefix}-redis-ec2-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" } }]
  })
  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "runtime" {
  name = "${var.name_prefix}-redis-runtime"
  role = aws_iam_role.instance.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ssm:GetParameter", "ssm:GetParameters"], Resource = [aws_ssm_parameter.username.arn, local.password_parameter_arn] },
      { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.redis.arn}:*" },
    ]
  })
}

resource "aws_iam_instance_profile" "redis" {
  name = "${var.name_prefix}-redis-profile"
  role = aws_iam_role.instance.name
  tags = var.common_tags
}

resource "aws_instance" "redis" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.redis.id]
  iam_instance_profile        = aws_iam_instance_profile.redis.name
  ebs_optimized               = true
  user_data                   = file("${path.module}/templates/bootstrap.sh")
  user_data_replace_on_change = false
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }
  credit_specification { cpu_credits = "standard" }
  root_block_device {
    encrypted             = true
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gib
    delete_on_termination = true
    tags                  = merge(var.common_tags, { Name = "${var.name_prefix}-redis-root" })
  }
  tags = merge(var.common_tags, { Name = "${var.name_prefix}-redis" })
  lifecycle {
    prevent_destroy = true
    precondition {
      condition     = data.aws_ami.redis.architecture == "x86_64"
      error_message = "Redis t3a requires a pinned x86_64 AMI."
    }
  }
  depends_on = [aws_iam_role_policy_attachment.ssm, aws_iam_role_policy.runtime, aws_vpc_security_group_egress_rule.outbound]
}

# Settings deployment is separate from the host. No secret values in user data or SSM document.
resource "aws_ssm_document" "configure" {
  name            = "${var.name_prefix}-redis-configure"
  document_type   = "Command"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Configure the private Redis EC2 container using runtime SSM credentials"
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "configureRedis"
      inputs = {
        timeoutSeconds = "1200"
        runCommand = ["bash -se <<'ZipsaiRedisConfigure'\n${templatefile("${path.module}/templates/configure.sh.tftpl", {
          aws_region         = var.aws_region
          image_version      = var.image_version
          username_parameter = aws_ssm_parameter.username.name
          password_parameter = local.password_parameter_name
          password_version   = var.password_version
          maxmemory_mib      = var.maxmemory_mib
          log_group          = aws_cloudwatch_log_group.redis.name
        })}\nZipsaiRedisConfigure"]
      }
    }]
  })
  tags = var.common_tags
}

resource "aws_ssm_association" "configure" {
  name             = aws_ssm_document.configure.name
  document_version = aws_ssm_document.configure.latest_version
  targets {
    key    = "InstanceIds"
    values = [aws_instance.redis.id]
  }
  wait_for_success_timeout_seconds = 1200
}

resource "aws_route53_record" "redis" {
  zone_id    = var.private_dns_zone_id
  name       = local.endpoint
  type       = "A"
  ttl        = 30
  records    = [aws_instance.redis.private_ip]
  depends_on = [aws_ssm_association.configure]
}
