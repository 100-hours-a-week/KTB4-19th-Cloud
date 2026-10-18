variable "redis_ami_id" {
  description = "Pinned official Ubuntu 24.04 amd64 AMI (verified 2026-10-16 in Seoul)."
  type        = string
  default     = "ami-0c713e716602facc2"
}

variable "redis_instance_type" {
  type    = string
  default = "t3a.small"
}

variable "redis_root_volume_size_gib" {
  type    = number
  default = 16
}

variable "redis_maxmemory_mib" {
  description = "Initial Redis memory budget; not total EC2/process RAM. Tune after load verification."
  type        = number
  default     = 128
}

variable "redis_image_version" {
  description = "Official Redis image tag managed by Terraform."
  type        = string
  default     = "8.2.10"
}

variable "redis_username" {
  description = "Initial Redis ACL username. Empty selects the authenticated default user."
  type        = string
  default     = "zipsai_app"
}

variable "redis_password_version" {
  description = "Increment after manually rotating /zipsai/prod/redis/password to trigger Redis configuration deployment, then redeploy clients."
  type        = number
  default     = 1
}
