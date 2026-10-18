variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "common_tags" { type = map(string) }
variable "vpc_id" { type = string }
variable "subnet_id" { type = string }
variable "private_dns_zone_id" { type = string }
variable "client_security_group_ids" { type = map(string) }
variable "aws_region" { type = string }

variable "image_version" {
  description = "Pinned official Redis container tag on EC2; not deployed by Backend CD."
  type        = string
  default     = "8.2.10"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.image_version))
    error_message = "Use a pinned numeric Redis image tag."
  }
}

variable "ami_id" {
  description = "Pinned Canonical Ubuntu 24.04 x86_64 AMI."
  type        = string
}
variable "instance_type" {
  type    = string
  default = "t3a.small"
  validation {
    condition     = can(regex("^t3a\\.", var.instance_type))
    error_message = "Keep Redis on the agreed x86_64 t3a family."
  }
}
variable "root_volume_size_gib" {
  type    = number
  default = 16
  validation {
    condition     = var.root_volume_size_gib >= 8 && floor(var.root_volume_size_gib) == var.root_volume_size_gib
    error_message = "Root gp3 volume must be an integer of at least 8 GiB."
  }
}
variable "maxmemory_mib" {
  description = "Redis maxmemory, not the full process/host memory limit. Leave headroom for OS and Redis overhead."
  type        = number
  default     = 128
  validation {
    condition     = var.maxmemory_mib > 0 && floor(var.maxmemory_mib) == var.maxmemory_mib
    error_message = "maxmemory_mib must be a positive integer."
  }
}

variable "username" {
  description = "Initial Redis ACL user; empty uses the authenticated default user."
  type        = string
  default     = "zipsai_app"
  validation {
    condition     = var.username == "" || can(regex("^[A-Za-z0-9_-]+$", var.username))
    error_message = "Redis username must be empty or contain only letters, digits, underscore and dash."
  }
}

variable "password_version" {
  description = "Configuration redeploy revision: increment after externally rotating the SecureString. Does not write a Parameter version."
  type        = number
  default     = 1
}
