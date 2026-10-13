locals {
  cache_name    = "${var.name_prefix}-valkey"
  user_id       = "${var.name_prefix}-valkey-app"
  user_group_id = "${var.name_prefix}-valkey-users"
  username      = "zipsai_app"
}

resource "aws_security_group" "valkey" {
  name        = "${local.cache_name}-sg"
  description = "Allow Valkey access only from application tasks"
  vpc_id      = var.vpc_id

  revoke_rules_on_delete = true

  tags = merge(var.common_tags, {
    Name = "${local.cache_name}-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "client" {
  for_each = var.client_security_group_ids

  security_group_id            = aws_security_group.valkey.id
  referenced_security_group_id = each.value
  description                  = "Valkey TLS from ${each.key} tasks"
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"

  tags = merge(var.common_tags, {
    Name = "${local.cache_name}-from-${each.key}"
  })
}

resource "aws_elasticache_user" "application" {
  user_id       = local.user_id
  user_name     = local.username
  access_string = "on ~* &* +@all"
  engine        = "valkey"

  passwords_wo         = var.password
  passwords_wo_version = var.password_version

  tags = merge(var.common_tags, {
    Name = local.user_id
  })
}

resource "aws_elasticache_user_group" "application" {
  engine        = "valkey"
  user_group_id = local.user_group_id
  user_ids      = [aws_elasticache_user.application.user_id]

  tags = merge(var.common_tags, {
    Name = local.user_group_id
  })
}

resource "aws_elasticache_serverless_cache" "this" {
  name                 = local.cache_name
  description          = "Shared rate limit and SSE state for ${var.name_prefix}"
  engine               = "valkey"
  major_engine_version = var.major_engine_version
  network_type         = "ipv4"

  subnet_ids         = var.subnet_ids
  security_group_ids = [aws_security_group.valkey.id]
  user_group_id      = aws_elasticache_user_group.application.user_group_id

  cache_usage_limits {
    data_storage {
      maximum = var.maximum_data_storage_gb
      unit    = "GB"
    }

    ecpu_per_second {
      maximum = var.maximum_ecpu_per_second
    }
  }

  tags = merge(var.common_tags, {
    Name = local.cache_name
  })
}

resource "aws_ssm_parameter" "password" {
  name        = var.ssm_parameter_name
  description = "Application password for ${local.cache_name}"
  type        = "SecureString"
  tier        = "Standard"

  value_wo         = var.password
  value_wo_version = var.password_version

  tags = merge(var.common_tags, {
    Name = var.ssm_parameter_name
  })
}
