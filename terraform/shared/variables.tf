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

variable "production_frontend_alias_target" {
  description = "Null keeps the V1 apex IP. Set only after V2 CloudFront TLS/aliases are deployed and cutover is approved; keep the selected value in future shared plans."
  type = object({
    domain_name = string
    zone_id     = string
  })
  default  = null
  nullable = true
  validation {
    condition = var.production_frontend_alias_target == null ? true : (
      endswith(var.production_frontend_alias_target.domain_name, ".cloudfront.net") &&
      var.production_frontend_alias_target.zone_id == "Z2FDTNDATAQYW2"
    )
    error_message = "Use the approved V2 CloudFront domain and global CloudFront Route 53 zone ID."
  }
}

