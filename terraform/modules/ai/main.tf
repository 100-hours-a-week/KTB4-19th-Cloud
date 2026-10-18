data "aws_ami" "host" {
  owners = ["099720109477"]
  filter {
    name   = "image-id"
    values = [var.ami_id]
  }
}

locals {
  hosts = {
    ai-api    = { port = 8000 }
    embedding = { port = 8000 }
    qdrant    = { port = 6333 }
  }
  dns_names = { for name in keys(local.hosts) : name => "${name}.${var.environment}.zipsai.internal" }
  runtime_defaults = {
    ai-api = merge({
      QDRANT_COLLECTION            = "documents"
      LLM_BASE_URL                 = ""
      LLM_MODEL                    = ""
      VLM_MODEL                    = ""
      LLM_TIMEOUT_SECONDS          = "30"
      LANGFUSE_BASE_URL            = "https://cloud.langfuse.com"
      LANGFUSE_TRACING_ENABLED     = "true"
      LANGFUSE_TRACING_ENVIRONMENT = var.environment == "prod" ? "production" : "staging"
      }, var.api_environment, {
      QDRANT_URL        = "http://${local.dns_names.qdrant}:6333"
      EMBEDDING_API_URL = "http://${local.dns_names.embedding}:8000"
      S3_BUCKET         = var.uploads_bucket_name
      AWS_REGION        = var.aws_region
      TZ                = "Asia/Seoul"
    })
    embedding = merge({
      LANGFUSE_BASE_URL            = "https://cloud.langfuse.com"
      LANGFUSE_TRACING_ENABLED     = "true"
      LANGFUSE_TRACING_ENVIRONMENT = var.environment == "prod" ? "production" : "staging"
    }, var.embedding_environment)
    qdrant = {}
  }
  host_manifests = {
    for name in keys(local.hosts) : name => {
      service            = name
      region             = var.aws_region
      runtime_parameter  = aws_ssm_parameter.runtime[name].name
      runtime_parameters = var.runtime_parameter_names[name]
      secret_parameters  = var.secret_parameter_names[name]
      repository_url     = lookup(var.image_repository_urls, name, "")
      qdrant_version     = var.qdrant_image_version
      port               = local.hosts[name].port
    }
  }
  host_install_scripts = {
    for name in keys(local.hosts) : name => templatefile("${path.module}/templates/install.sh.tftpl", {
      manifest_base64 = base64encode(jsonencode(local.host_manifests[name]))
      compose_base64 = base64encode(templatefile("${path.module}/../../../compose/ai/compose-${name}.yml.tftpl", {
        repository_url = lookup(var.image_repository_urls, name, "")
        log_group      = aws_cloudwatch_log_group.host[name].name
        aws_region     = var.aws_region
        qdrant_version = var.qdrant_image_version
      }))
      prepare_base64 = base64encode(file("${path.module}/templates/prepare-env.py"))
      deploy_base64  = base64encode(file("${path.module}/templates/deploy.sh"))
    })
  }
}

resource "aws_security_group" "host" {
  for_each    = local.hosts
  name        = "${var.name_prefix}-${each.key}-sg"
  description = "Private ${each.key} host; caller security groups only"
  vpc_id      = var.vpc_id
  tags        = merge(var.common_tags, { Name = "${var.name_prefix}-${each.key}-sg" })
}
resource "aws_vpc_security_group_ingress_rule" "api_clients" {
  for_each                     = var.client_security_group_ids
  security_group_id            = aws_security_group.host["ai-api"].id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
  tags                         = var.common_tags
}
resource "aws_vpc_security_group_ingress_rule" "dependencies" {
  for_each                     = { for name, host in local.hosts : name => host if name != "ai-api" }
  security_group_id            = aws_security_group.host[each.key].id
  referenced_security_group_id = aws_security_group.host["ai-api"].id
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  tags                         = var.common_tags
}
resource "aws_vpc_security_group_egress_rule" "outbound" {
  for_each          = local.hosts
  security_group_id = aws_security_group.host[each.key].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "NAT for bootstrap, image pulls, SSM, logs and external HTTPS"
  tags              = var.common_tags
}
resource "aws_cloudwatch_log_group" "host" {
  for_each          = local.hosts
  name              = "${var.log_group_prefix != null ? var.log_group_prefix : "/zipsai/${var.environment}"}/${each.key}"
  retention_in_days = 14
  tags              = var.common_tags
}
resource "aws_ssm_parameter" "runtime" {
  for_each = local.hosts
  name     = "/zipsai/${var.environment}/ai/${each.key}/runtime"
  type     = "String"
  value    = jsonencode(local.runtime_defaults[each.key])
  tags     = var.common_tags
  lifecycle { ignore_changes = [value] }
}
resource "aws_iam_role" "host" {
  for_each = local.hosts
  name     = "${var.name_prefix}-${each.key}-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" } }]
  })
  tags = var.common_tags
}
resource "aws_iam_role_policy_attachment" "ssm" {
  for_each   = local.hosts
  role       = aws_iam_role.host[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
data "aws_caller_identity" "current" {}
resource "aws_iam_role_policy" "runtime" {
  for_each = local.hosts
  name     = "${var.name_prefix}-${each.key}-runtime"
  role     = aws_iam_role.host[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Effect = "Allow", Action = ["ssm:GetParameter", "ssm:GetParameters"],
        Resource = concat([aws_ssm_parameter.runtime[each.key].arn], [
          for path in concat(values(var.secret_parameter_names[each.key]), values(var.runtime_parameter_names[each.key])) :
          "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${path}"
        ])
      },
      {
        Effect   = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = "${aws_cloudwatch_log_group.host[each.key].arn}:*"
      },
      {
        # ManagedInstanceCore grants GetParameter(s) on '*'; constrain these new roles.
        Effect = "Deny", Action = ["ssm:GetParameter", "ssm:GetParameters"],
        NotResource = concat([aws_ssm_parameter.runtime[each.key].arn], [
          for path in concat(values(var.secret_parameter_names[each.key]), values(var.runtime_parameter_names[each.key])) :
          "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${path}"
        ])
      },
      {
        Effect   = "Deny", Action = ["ssm:GetParametersByPath", "ssm:GetParameterHistory"],
        Resource = "*"
      }
      ], each.key != "qdrant" ? [
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      { Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"], Resource = var.image_repository_arns[each.key] }
      ] : [], each.key == "ai-api" ? [
      { Effect = "Allow", Action = ["s3:GetObject"], Resource = "arn:aws:s3:::${var.uploads_bucket_name}/*" }
      ] : [], length(var.kms_key_arns) > 0 ? [
      { Effect = "Allow", Action = ["kms:Decrypt"], Resource = var.kms_key_arns }
    ] : [])
  })
}
resource "aws_iam_instance_profile" "host" {
  for_each = local.hosts
  name     = "${var.name_prefix}-${each.key}-profile"
  role     = aws_iam_role.host[each.key].name
  tags     = var.common_tags
}
resource "aws_ebs_volume" "qdrant" {
  availability_zone = var.availability_zone
  encrypted         = true
  type              = "gp3"
  size              = var.qdrant_data_volume_size_gib
  tags              = merge(var.common_tags, { Name = "${var.name_prefix}-qdrant-data" })
  lifecycle { prevent_destroy = true }
}
resource "aws_instance" "host" {
  for_each                    = local.hosts
  ami                         = var.ami_id
  instance_type               = var.instance_types[each.key]
  subnet_id                   = var.subnet_id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.host[each.key].id]
  iam_instance_profile        = aws_iam_instance_profile.host[each.key].name
  ebs_optimized               = true
  user_data_replace_on_change = false
  user_data = templatefile("${path.module}/templates/bootstrap.sh.tftpl", {
    data_volume_id = each.key == "qdrant" ? replace(aws_ebs_volume.qdrant.id, "-", "") : ""
  })
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }
  credit_specification { cpu_credits = "standard" }
  root_block_device {
    encrypted             = true
    volume_type           = "gp3"
    volume_size           = var.root_volume_sizes[each.key]
    delete_on_termination = true
    tags                  = merge(var.common_tags, { Name = "${var.name_prefix}-${each.key}-root" })
  }
  tags = merge(var.common_tags, { Name = "${var.name_prefix}-${each.key}" })
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [user_data]
    precondition {
      condition     = data.aws_ami.host.architecture == "x86_64"
      error_message = "AI API and Embedding images require amd64."
    }
  }
  depends_on = [aws_iam_role_policy_attachment.ssm, aws_iam_role_policy.runtime, aws_vpc_security_group_egress_rule.outbound]
}

# No association: Terraform prepares the contract; CD/user explicitly starts deployments.
resource "aws_ssm_document" "deploy" {
  for_each        = local.hosts
  name            = "${var.name_prefix}-${each.key}-deploy"
  document_type   = "Command"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Deploy private ${each.key} from explicit image tag and existing SSM configuration"
    parameters = {
      ImageTag = { type = "String", default = "", allowedPattern = "^([0-9a-f]{7})?$" }
    }
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "deploy"
      inputs = {
        timeoutSeconds = "1800"
        runCommand     = ["bash -se <<'ZipsaiAiDeploy'\nset +x\ncloud-init status --wait >/dev/null\nexec 9>/run/zipsai-ai-deploy.lock\nflock -w 900 9\n${local.host_install_scripts[each.key]}\nZIPSAI_AI_LOCK_HELD=1 /opt/zipsai/deploy.sh '{{ ImageTag }}'\nZipsaiAiDeploy"]
      }
    }]
  })
  tags = var.common_tags
}
resource "aws_volume_attachment" "qdrant" {
  device_name                    = "/dev/sdf"
  instance_id                    = aws_instance.host["qdrant"].id
  volume_id                      = aws_ebs_volume.qdrant.id
  stop_instance_before_detaching = true
}
resource "aws_route53_record" "host" {
  for_each = local.hosts
  zone_id  = var.private_dns_zone_id
  name     = local.dns_names[each.key]
  type     = "A"
  ttl      = 30
  records  = [aws_instance.host[each.key].private_ip]
}
