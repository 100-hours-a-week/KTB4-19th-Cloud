variable "aws_region" {
  description = "AWS Region in which the Terraform state bucket is created."
  type        = string
  default     = "ap-northeast-2"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name used by Terraform backends."
  type        = string
  default     = "zipsai-v2-terraform-state"
}

variable "common_tags" {
  description = "Tags applied to resources managed by this root module."
  type        = map(string)
  default = {
    Project     = "zipsai"
    Environment = "shared"
    ManagedBy   = "terraform"
  }
}
