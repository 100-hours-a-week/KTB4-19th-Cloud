variable "aws_region" {
  description = "AWS Region for the Staging environment."
  type        = string
  default     = "ap-northeast-2"
}

variable "mysql_ami_id" {
  description = "Packer-built Ubuntu 24.04 x86_64 MySQL 8.4.11 AMI."
  type        = string
  default     = "ami-0bf77c0461e38e97c"
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

variable "backend_image_tag" {
  description = "Immutable Backend image tag deployed to ECS."
  type        = string
  default     = "c90b266"
}

variable "api_desired_count" {
  description = "Staging API task count. Raise to two after DB and Parameter Store validation."
  type        = number
  default     = 0
}

variable "worker_desired_count" {
  description = "Staging Worker task count. Raise to one after Worker mode is implemented."
  type        = number
  default     = 0
}

variable "worker_command" {
  description = "Staging Worker command supplied after the Backend image supports Worker mode."
  type        = list(string)
  default     = []
}

variable "ai_api_url" {
  description = "RunPod AI API endpoint supplied before the ECS API service starts."
  type        = string
  default     = "https://runpod-endpoint-to-be-configured.invalid"
}

variable "uploads_bucket_name" {
  description = "Staging upload bucket created separately from Production data."
  type        = string
  default     = "zipsai-staging-uploads"
}

variable "enable_custom_domains" {
  description = "Create ACM validation and Route 53 records after Gabia delegates DNS to Route 53."
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
  description = "Increment when rotating the Staging Valkey password."
  type        = number
  default     = 1
}
