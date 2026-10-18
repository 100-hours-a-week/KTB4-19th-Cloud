variable "name_prefix" {
  description = "Prefix used for monitoring resources."
  type        = string
}

variable "common_tags" {
  description = "Tags applied to monitoring resources."
  type        = map(string)
}

variable "aws_region" {
  description = "AWS Region containing the monitoring stack."
  type        = string
}

variable "subnet_id" {
  description = "Private application subnet used by the monitoring instance."
  type        = string
}

variable "security_group_id" {
  description = "Security group attached to the monitoring instance."
  type        = string
}

variable "private_dns_zone_id" {
  description = "Private Route 53 hosted zone ID."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type running Prometheus, Loki, and Grafana."
  type        = string
  default     = "t3a.medium"
}

variable "data_volume_size_gib" {
  description = "Persistent gp3 volume size for monitoring data."
  type        = number
  default     = 30
}

variable "grafana_admin_password_parameter_name" {
  description = "SecureString Parameter Store name containing the Grafana admin password."
  type        = string
}

variable "ami_id" {
  description = "Pinned monitoring AMI. Changing it requires an explicit instance replacement review."
  type        = string
}
