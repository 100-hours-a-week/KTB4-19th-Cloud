variable "name_prefix" {
  description = "Prefix used for Frontend resources."
  type        = string
}

variable "common_tags" {
  description = "Tags applied to Frontend resources."
  type        = map(string)
}

variable "bucket_name" {
  description = "Globally unique private Frontend origin bucket name."
  type        = string
}

variable "domain_name" {
  description = "Optional custom domain attached after ACM validation."
  type        = string
  default     = null
  nullable    = true
}

variable "certificate_arn" {
  description = "Optional us-east-1 ACM certificate ARN for the custom domain."
  type        = string
  default     = null
  nullable    = true
}

variable "price_class" {
  description = "CloudFront price class. PriceClass_200 includes Asia."
  type        = string
  default     = "PriceClass_200"
}
