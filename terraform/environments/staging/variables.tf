variable "aws_region" {
  description = "AWS Region for the Staging environment."
  type        = string
  default     = "ap-northeast-2"
}

variable "mysql_ami_id" {
  description = "Packer-built Ubuntu 24.04 x86_64 MySQL 8.4.11 AMI."
  type        = string
  default     = "ami-09fdf482fdfe9f40f"
}

variable "mysql_instance_type" {
  description = "Staging MySQL Primary and Replica instance type."
  type        = string
  default     = "t3a.small"
}

variable "mysql_data_volume_size_gib" {
  description = "Staging MySQL data volume size per node."
  type        = number
  default     = 20
}

variable "enable_rehearsal_source" {
  description = "Temporarily connect the disposable V1-like source used for the Staging migration rehearsal."
  type        = bool
  default     = true
}

variable "rehearsal_source_security_group_id" {
  description = "Security group of the temporary V1-like source used only by the Staging rehearsal."
  type        = string
  default     = "sg-0b5cb3cd96f3313a6"

  validation {
    condition     = can(regex("^sg-[0-9a-f]+$", var.rehearsal_source_security_group_id))
    error_message = "rehearsal_source_security_group_id must be a valid security group ID."
  }
}

variable "rehearsal_source_ec2_role_name" {
  description = "IAM role of the temporary V1-like source used only by the Staging rehearsal."
  type        = string
  default     = "zipsai-load-test-ec2-role"
}

variable "rehearsal_source_private_ip" {
  description = "Private IP of the temporary V1-like MySQL source."
  type        = string
  default     = "10.0.1.124"

  validation {
    condition     = can(cidrhost("${var.rehearsal_source_private_ip}/32", 0))
    error_message = "rehearsal_source_private_ip must be a valid IPv4 address."
  }
}

variable "backend_image_tag" {
  description = "Immutable Backend image tag deployed to ECS."
  type        = string
  default     = "c90b266"
}

variable "api_desired_count" {
  description = "Single-task Staging API baseline for cost control; power scripts may temporarily suspend it."
  type        = number
  default     = 1
}

variable "worker_desired_count" {
  description = "Staging document outbox Worker baseline; QA daily scheduling remains disabled."
  type        = number
  default     = 1
}

variable "worker_command" {
  description = "Staging Worker command supplied after the Backend image supports Worker mode."
  type        = list(string)
  default     = []
}

variable "ai_api_url" {
  description = "Optional override; defaults to the environment's private AI API EC2 DNS."
  type        = string
  default     = null
}

variable "uploads_bucket_name" {
  description = "Staging upload bucket created separately from Production data."
  type        = string
  default     = "zipsai-staging-uploads"
}

variable "enable_custom_domains" {
  description = "Staging-only HTTPS and DNS for v2.zipsai.co.kr and api-v2.zipsai.co.kr. V1/prod are not switched."
  type        = bool
  default     = true
}
