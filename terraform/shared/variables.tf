variable "aws_region" {
  description = "AWS Region containing shared Zipsai resources."
  type        = string
  default     = "ap-northeast-2"
}

variable "shared_tags" {
  description = "Tags applied to resources shared by Staging and Production."
  type        = map(string)
  default = {
    Project     = "zipsai"
    Environment = "shared"
    ManagedBy   = "Terraform"
  }
}

