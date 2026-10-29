variable "ai_ami_id" {
  description = "Pinned Canonical Ubuntu 24.04 amd64 AMI (Seoul)."
  type        = string
  default     = "ami-0c713e716602facc2"
}
variable "ai_instance_types" {
  type = map(string)
  default = {
    ai-api    = "t3a.large"
    embedding = "t3a.large"
    qdrant    = "t3a.micro"
  }
}
variable "ai_root_volume_sizes" {
  type    = map(number)
  default = { ai-api = 40, embedding = 30, qdrant = 16 }
}
variable "qdrant_data_volume_size_gib" {
  type    = number
  default = 30
}
variable "ai_api_environment" {
  description = "Initial non-secret AI settings. Reuse existing values through runtime JSON, not hardcoded secrets."
  type        = map(string)
  default     = {}
}
variable "embedding_environment" {
  type    = map(string)
  default = {}
}
variable "ai_api_secret_parameter_names" {
  description = "Override SecureString paths (Langfuse secret key only; public key uses the String runtime map)."
  type        = map(string)
  default     = {}
}
variable "embedding_secret_parameter_names" {
  description = "Override existing SecureString paths, including the Langfuse secret key."
  type        = map(string)
  default     = {}
}
variable "ai_parameter_kms_key_arns" {
  description = "Optional customer-managed KMS keys used by the referenced SecureStrings."
  type        = list(string)
  default     = []
}

variable "qdrant_read_only_parameter_name" {
  description = "Existing Qdrant read-only SecureString path; confirm from the Parameter inventory."
  type        = string
  default     = null
}

variable "ai_api_runtime_parameter_names" {
  description = "Override non-secret String paths, including Langfuse public key/base URL and model settings."
  type        = map(string)
  default     = {}
}
variable "embedding_runtime_parameter_names" {
  type    = map(string)
  default = {}
}
