variable "enable_application_hosts" {
  description = "Keep the V2 AI API and Embedding hosts enabled. Qdrant and its data volume remain managed and protected."
  type        = bool
  default     = true
}

moved {
  from = aws_instance.host["qdrant"]
  to   = aws_instance.qdrant["qdrant"]
}
