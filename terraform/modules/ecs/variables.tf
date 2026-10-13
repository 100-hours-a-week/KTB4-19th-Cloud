variable "name_prefix" {
  description = "Prefix used for ECS and ALB resource names."
  type        = string
}

variable "environment" {
  description = "Environment label attached to logs sent to Loki."
  type        = string
}

variable "common_tags" {
  description = "Tags applied to all ECS and ALB resources."
  type        = map(string)
}

variable "vpc_id" {
  description = "VPC containing the ALB and ECS tasks."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs used by the internet-facing ALB."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "The ALB requires at least two public subnets."
  }
}

variable "private_app_subnet_ids" {
  description = "Private application subnet IDs used by ECS tasks."
  type        = list(string)

  validation {
    condition     = length(var.private_app_subnet_ids) >= 1
    error_message = "At least one private application subnet is required."
  }
}

variable "api_security_group_id" {
  description = "Security group attached to API tasks."
  type        = string
}

variable "worker_security_group_id" {
  description = "Security group attached to Worker tasks."
  type        = string
}

variable "monitoring_client_security_group_id" {
  description = "Security group authorizing ECS tasks to send logs to private Loki."
  type        = string
}

variable "loki_host" {
  description = "Private Loki hostname without scheme or port."
  type        = string
  default     = "loki.monitoring.zipsai.internal"
}

variable "loki_port" {
  description = "Private Loki HTTP ingestion port."
  type        = number
  default     = 3100
}

variable "firelens_image_uri" {
  description = "AWS for Fluent Bit image used by the FireLens log router."
  type        = string
  default     = "public.ecr.aws/aws-observability/aws-for-fluent-bit:stable"
}

variable "appconfig_agent_image_uri" {
  description = "AWS AppConfig Agent image used as an ECS sidecar."
  type        = string
  default     = "public.ecr.aws/aws-appconfig/aws-appconfig-agent:2.x"
}

variable "appconfig_application_name" {
  description = "AppConfig application name read by the Backend."
  type        = string
}

variable "appconfig_environment_name" {
  description = "AppConfig environment name read by the Backend."
  type        = string
}

variable "appconfig_profile_name" {
  description = "AppConfig configuration profile name read by the Backend."
  type        = string
}

variable "appconfig_configuration_arn" {
  description = "AppConfig data-plane configuration ARN available to API and Worker task roles."
  type        = string
}

variable "appconfig_poll_interval" {
  description = "How often the Agent checks AppConfig during migration."
  type        = string
  default     = "5s"
}

variable "backend_image_uri" {
  description = "Immutable Backend ECR image URI including its tag."
  type        = string
}

variable "api_environment" {
  description = "Non-secret environment variables for the API container."
  type        = map(string)
  default     = {}
}

variable "worker_environment" {
  description = "Non-secret environment variables for the Worker container."
  type        = map(string)
  default     = {}
}

variable "api_secrets" {
  description = "API environment variable names mapped to SSM Parameter ARNs."
  type        = map(string)
  default     = {}
}

variable "worker_secrets" {
  description = "Worker environment variable names mapped to SSM Parameter ARNs."
  type        = map(string)
  default     = {}
}

variable "worker_command" {
  description = "Command override used after the Backend image supports Worker mode."
  type        = list(string)
  default     = []
}

variable "api_desired_count" {
  description = "Number of API tasks. Keep at zero until DB and secrets are ready."
  type        = number
  default     = 0
}

variable "worker_desired_count" {
  description = "Number of Worker tasks. Keep at zero until Worker mode is ready."
  type        = number
  default     = 0
}

variable "uploads_bucket_name" {
  description = "Existing upload bucket used by the API and Worker."
  type        = string
}

variable "document_jobs_queue_arn" {
  description = "SQS queue ARN used for API publishing and Worker consumption."
  type        = string
}

variable "certificate_arn" {
  description = "Optional ACM certificate ARN. Null keeps the validation listener on HTTP."
  type        = string
  default     = null
  nullable    = true
}

variable "health_check_path" {
  description = "ALB readiness path exposed by the API."
  type        = string
  default     = "/api/actuator/health/readiness"
}

variable "liveness_check_path" {
  description = "Container liveness path exposed by the API."
  type        = string
  default     = "/api/actuator/health/liveness"
}
