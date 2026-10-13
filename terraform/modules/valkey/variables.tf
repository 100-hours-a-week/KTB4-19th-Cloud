variable "name_prefix" {
  description = "Prefix used for Valkey resource names."
  type        = string
}

variable "common_tags" {
  description = "Tags applied to Valkey resources."
  type        = map(string)
}

variable "vpc_id" {
  description = "VPC where the Valkey endpoint is created."
  type        = string
}

variable "subnet_ids" {
  description = "Private Data subnet IDs used by ElastiCache Serverless."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least two private Data subnets are required."
  }
}

variable "client_security_group_ids" {
  description = "Security groups allowed to connect to the Valkey primary endpoint."
  type        = map(string)

  validation {
    condition     = length(var.client_security_group_ids) > 0
    error_message = "At least one client security group is required."
  }
}

variable "password" {
  description = "Valkey application password supplied only during plan/apply."
  type        = string
  sensitive   = true
  ephemeral   = true

  validation {
    condition     = length(var.password) >= 16 && length(var.password) <= 128
    error_message = "The Valkey password must be between 16 and 128 characters."
  }
}

variable "password_version" {
  description = "Increment this value when rotating the Valkey password."
  type        = number
  default     = 1

  validation {
    condition     = var.password_version >= 1 && floor(var.password_version) == var.password_version
    error_message = "password_version must be a positive integer."
  }
}

variable "ssm_parameter_name" {
  description = "SSM SecureString parameter that stores the Valkey password."
  type        = string
}

variable "major_engine_version" {
  description = "Valkey major engine version."
  type        = string
  default     = "8"
}

variable "maximum_data_storage_gb" {
  description = "Maximum data storage consumed by the serverless cache."
  type        = number
  default     = 1
}

variable "maximum_ecpu_per_second" {
  description = "Maximum ECPU consumed per second by the serverless cache."
  type        = number
  default     = 1000
}
