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

variable "additional_domain_names" {
  description = "Additional aliases covered by certificate_arn; empty preserves single-domain users."
  type        = list(string)
  default     = []
}

variable "canonical_domain_name" {
  description = "Optional canonical host; redirect its www alias while preserving path and query."
  type        = string
  default     = null
  nullable    = true
}

variable "price_class" {
  description = "CloudFront price class. PriceClass_200 includes Asia."
  type        = string
  default     = "PriceClass_200"
}

variable "api_origin_domain_name" {
  description = "Optional HTTPS API origin. Null preserves the existing S3-only distribution."
  type        = string
  default     = null
  nullable    = true
}

variable "enable_api_proxy" {
  description = "Forward /api paths to the API origin; disabling requires a canonical host for explicit 404 responses."
  type        = bool
  default     = true
  validation {
    condition     = var.enable_api_proxy || var.canonical_domain_name != null
    error_message = "Disabling the API proxy requires canonical_domain_name."
  }
}
