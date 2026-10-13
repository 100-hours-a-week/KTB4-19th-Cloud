variable "aws_region" {
  description = "AWS Region containing the monitoring stack."
  type        = string
  default     = "ap-northeast-2"
}

variable "instance_type" {
  description = "EC2 instance type running Prometheus, Loki, and Grafana."
  type        = string
  default     = "t3a.medium"
}

variable "data_volume_size_gib" {
  description = "Persistent gp3 volume size for 30 days of monitoring data."
  type        = number
  default     = 30
}

variable "grafana_admin_password_parameter_name" {
  description = "Existing SecureString Parameter Store name containing the Grafana admin password."
  type        = string
  default     = "/zipsai/monitoring/grafana/admin-password"
}

variable "legacy_mysql_private_ip" {
  description = "Private IP of the existing V1 EC2 that exposes temporary migration exporters."
  type        = string
  default     = "10.0.1.239"

  validation {
    condition     = can(cidrhost("${var.legacy_mysql_private_ip}/32", 0))
    error_message = "legacy_mysql_private_ip must be a valid IPv4 address."
  }
}
