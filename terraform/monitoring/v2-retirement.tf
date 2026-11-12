variable "enable_v2_application_observability" {
  description = "Discover the retired V2 AI API and Embedding EC2s. Qdrant and MySQL collection remain enabled."
  type        = bool
  default     = true
}
