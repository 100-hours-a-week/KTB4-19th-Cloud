variable "aws_region" {
  description = "AWS Region containing the shared V2 network."
  type        = string
  default     = "ap-northeast-2"
}

variable "shared_tags" {
  description = "Tags applied to new network resources shared by staging and production."
  type        = map(string)
  default = {
    Project     = "zipsai"
    Environment = "shared"
    ManagedBy   = "Terraform"
  }
}

variable "legacy_service_security_group_id" {
  description = "Existing V1 service security group that receives Prometheus scrapes during migration."
  type        = string
  default     = "sg-0a4b86875aa8535b7"

  validation {
    condition     = can(regex("^sg-[0-9a-f]+$", var.legacy_service_security_group_id))
    error_message = "legacy_service_security_group_id must be a valid security group ID."
  }
}
