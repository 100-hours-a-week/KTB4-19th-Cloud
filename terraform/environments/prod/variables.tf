variable "aws_region" {
  description = "AWS Region for the Production environment."
  type        = string
  default     = "ap-northeast-2"
}

variable "mysql_ami_id" {
  description = "Packer-built Ubuntu 24.04 x86_64 MySQL 8.4.11 AMI."
  type        = string
  default     = "ami-0bf77c0461e38e97c"
}

variable "mysql_instance_type" {
  description = "Production MySQL Primary and Replica instance type."
  type        = string
  default     = "t3a.small"
}

variable "mysql_data_volume_size_gib" {
  description = "Production MySQL data volume size per node."
  type        = number
  default     = 20
}

variable "legacy_backend_security_group_id" {
  description = "Existing V1 Backend security group allowed to connect during database migration."
  type        = string
  default     = "sg-0a4b86875aa8535b7"

  validation {
    condition     = can(regex("^sg-[0-9a-f]+$", var.legacy_backend_security_group_id))
    error_message = "legacy_backend_security_group_id must be a valid security group ID."
  }
}

variable "legacy_ec2_role_name" {
  description = "Existing V1 EC2 IAM role granted read access to the Production AppConfig profile."
  type        = string
  default     = "zipsai-prod-ec2-role"
}

variable "backend_image_tag" {
  description = "Immutable Backend image tag deployed to ECS."
  type        = string
  default     = "c90b266"
}

variable "api_desired_count" {
  description = "Production API task count. Raise to two after DB migration and configuration validation."
  type        = number
  default     = 0
}

variable "worker_desired_count" {
  description = "Production Worker task count. Raise to one after Worker mode is implemented."
  type        = number
  default     = 0
}

variable "worker_command" {
  description = "Production Worker command supplied after the Backend image supports Worker mode."
  type        = list(string)
  default     = []
}

variable "ai_api_url" {
  description = "RunPod AI API endpoint supplied before the ECS API service starts."
  type        = string
  default     = "https://runpod-endpoint-to-be-configured.invalid"
}

variable "uploads_bucket_name" {
  description = "Existing Production upload bucket."
  type        = string
  default     = "zipsai-prod-uploads"
}

variable "enable_custom_domains" {
  description = "Create ACM validation and Route 53 records only during the approved DNS cutover."
  type        = bool
  default     = false
}

variable "valkey_password" {
  description = "Valkey password supplied only during plan/apply and never stored in State."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "valkey_password_version" {
  description = "Increment when rotating the Production Valkey password."
  type        = number
  default     = 1
}
