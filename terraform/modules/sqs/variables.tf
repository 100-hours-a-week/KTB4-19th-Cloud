variable "name_prefix" {
  description = "Environment-specific prefix used for SQS resource names."
  type        = string
}

variable "common_tags" {
  description = "Tags applied to SQS and alarm resources."
  type        = map(string)
}

variable "visibility_timeout_seconds" {
  description = "Initial period during which a received message remains hidden."
  type        = number
  default     = 30

  validation {
    condition     = var.visibility_timeout_seconds >= 0 && var.visibility_timeout_seconds <= 43200
    error_message = "visibility_timeout_seconds must be between 0 and 43200."
  }
}

variable "receive_wait_time_seconds" {
  description = "Long polling duration for ReceiveMessage."
  type        = number
  default     = 20

  validation {
    condition     = var.receive_wait_time_seconds >= 0 && var.receive_wait_time_seconds <= 20
    error_message = "receive_wait_time_seconds must be between 0 and 20."
  }
}

variable "message_retention_seconds" {
  description = "Main queue message retention period."
  type        = number
  default     = 345600
}

variable "dlq_message_retention_seconds" {
  description = "DLQ message retention period."
  type        = number
  default     = 1209600
}

variable "max_receive_count" {
  description = "Number of failed receives before SQS moves a message to the DLQ."
  type        = number
  default     = 3

  validation {
    condition     = var.max_receive_count >= 1
    error_message = "max_receive_count must be at least 1."
  }
}

variable "alarm_action_arns" {
  description = "SNS or other action ARNs notified when the DLQ alarm changes state."
  type        = list(string)
  default     = []
}

