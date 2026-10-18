variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "log_group_prefix" {
  description = "Optional separate log namespace to avoid taking over existing service logs."
  type        = string
  default     = null
}
variable "common_tags" { type = map(string) }
variable "aws_region" { type = string }
variable "vpc_id" { type = string }
variable "subnet_id" { type = string }
variable "availability_zone" { type = string }
variable "private_dns_zone_id" { type = string }
variable "ami_id" { type = string }
variable "client_security_group_ids" { type = map(string) }
variable "uploads_bucket_name" { type = string }
variable "image_repository_urls" { type = map(string) }
variable "image_repository_arns" { type = map(string) }
variable "instance_types" {
  type = map(string)
  default = {
    ai-api    = "t3a.large"
    embedding = "t3a.large"
    qdrant    = "t3a.small"
  }
  validation {
    condition     = alltrue([for k in ["ai-api", "embedding", "qdrant"] : can(regex("^t3a\\.", var.instance_types[k]))])
    error_message = "All three AI hosts must use the agreed x86_64 t3a family."
  }
}
variable "root_volume_sizes" {
  type    = map(number)
  default = { ai-api = 40, embedding = 30, qdrant = 16 }
  validation {
    condition     = alltrue([for k in ["ai-api", "embedding", "qdrant"] : try(var.root_volume_sizes[k] >= 8 && floor(var.root_volume_sizes[k]) == var.root_volume_sizes[k], false)])
    error_message = "Each host needs an integer root volume size of at least 8 GiB."
  }
}
variable "qdrant_data_volume_size_gib" {
  type    = number
  default = 30
  validation {
    condition     = var.qdrant_data_volume_size_gib >= 20 && floor(var.qdrant_data_volume_size_gib) == var.qdrant_data_volume_size_gib
    error_message = "Qdrant data volume must be an integer of at least 20 GiB."
  }
}
variable "qdrant_image_version" {
  type    = string
  default = "v1.19.1"
  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.qdrant_image_version))
    error_message = "Pin a numeric Qdrant release tag."
  }
}
variable "api_environment" {
  description = "Non-secret initial settings only. Existing runtime Parameter value is console/CD managed."
  type        = map(string)
  default     = {}
  validation {
    condition = length(setintersection(toset(keys(var.api_environment)), toset([
      "LLM_API_KEY", "OPENROUTER_API_KEY", "QDRANT_API_KEY", "QDRANT_ADMIN_API_KEY",
      "QDRANT_READ_ONLY_API_KEY", "LANGFUSE_SECRET_KEY",
      "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN"
    ]))) == 0
    error_message = "Do not place credentials in String runtime settings. Use existing SecureString paths."
  }
}
variable "embedding_environment" {
  description = "Non-secret initial settings only."
  type        = map(string)
  default     = {}
  validation {
    condition = length(setintersection(toset(keys(var.embedding_environment)), toset([
      "QDRANT_API_KEY", "QDRANT_ADMIN_API_KEY", "LANGFUSE_SECRET_KEY",
      "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN"
    ]))) == 0
    error_message = "Do not place credentials in String runtime settings."
  }
}
variable "secret_parameter_names" {
  description = "Existing SecureString paths by host and environment variable. Terraform never reads their values."
  type        = map(map(string))
  validation {
    condition     = alltrue([for host in ["ai-api", "embedding", "qdrant"] : contains(keys(var.secret_parameter_names), host)])
    error_message = "Provide the secret path map for each of the three hosts (embedding may be empty)."
  }
  validation {
    condition     = alltrue(flatten([for mapping in values(var.secret_parameter_names) : [for path in values(mapping) : startswith(path, "/")]]))
    error_message = "Use existing absolute Parameter names, not values or ARNs."
  }
}
variable "runtime_parameter_names" {
  description = "Existing non-secret per-variable Parameter paths; mapped values override initial runtime JSON defaults."
  type        = map(map(string))
  default     = { ai-api = {}, embedding = {}, qdrant = {} }
}
variable "kms_key_arns" {
  description = "Optional customer-managed KMS keys for existing SecureString parameters."
  type        = list(string)
  default     = []
}
