variable "enable_v3_data_access" {
  description = "Allow V3 nodes/pods to reach the existing MySQL and Qdrant services during integration."
  type        = bool
  default     = false
}

variable "v3_data_access_environments" {
  description = "Environments whose existing data services accept V3 access when enabled."
  type        = set(string)
  default     = ["staging", "prod"]

  validation {
    condition     = alltrue([for environment in var.v3_data_access_environments : contains(["staging", "prod"], environment)])
    error_message = "Only staging and prod data access environments are supported."
  }
}

locals {
  v3_data_targets = {
    staging-mysql  = { environment = "staging", name = "mysql", port = 3306 }
    staging-qdrant = { environment = "staging", name = "qdrant", port = 6333 }
    prod-mysql     = { environment = "prod", name = "mysql", port = 3306 }
    prod-qdrant    = { environment = "prod", name = "qdrant", port = 6333 }
  }

  v3_enabled_data_targets = {
    for key, target in local.v3_data_targets : key => target
    if var.enable_v3_data_access && contains(var.v3_data_access_environments, target.environment)
  }
}

data "aws_security_group" "v3_data_target" {
  for_each = local.v3_enabled_data_targets

  vpc_id = data.aws_vpc.shared.id
  tags = {
    Name = "zipsai-${each.value.environment}-${each.value.name}-sg"
  }
}

data "aws_instances" "v3_data_target" {
  for_each = local.v3_enabled_data_targets

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.shared.id]
  }
  filter {
    name   = "tag:Name"
    values = ["zipsai-${each.value.environment}-${each.value.name}${each.value.name == "mysql" ? "-*" : ""}"]
  }
  instance_state_names = ["running", "stopped"]
}

resource "aws_vpc_security_group_ingress_rule" "v3_data_access" {
  for_each = data.aws_security_group.v3_data_target

  security_group_id            = each.value.id
  referenced_security_group_id = aws_eks_cluster.v3.vpc_config[0].cluster_security_group_id
  description                  = "V3 EKS access; environment and workload isolation enforced by NetworkPolicy"
  ip_protocol                  = "tcp"
  from_port                    = local.v3_data_targets[each.key].port
  to_port                      = local.v3_data_targets[each.key].port
  tags                         = local.v3_tags
}

output "platform_database_cidrs" {
  description = "Actual external data-service IPs for network policy values, populated when integration access is enabled."
  value = {
    for environment in ["staging", "prod"] : environment => {
      mysqlCidrs  = try([for ip in data.aws_instances.v3_data_target["${environment}-mysql"].private_ips : "${ip}/32"], [])
      qdrantCidrs = try([for ip in data.aws_instances.v3_data_target["${environment}-qdrant"].private_ips : "${ip}/32"], [])
    }
  }
}
