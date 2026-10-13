variable "aws_profile" {
  type        = string
  description = "AWS CLI profile used by Packer."
  default     = "terraform"
}

variable "aws_region" {
  type        = string
  description = "AWS Region in which the AMI is built."
  default     = "ap-northeast-2"
}

variable "build_vpc_id" {
  type        = string
  description = "VPC used by the temporary Packer instance."
  default     = ""
}

variable "build_subnet_id" {
  type        = string
  description = "Public subnet used by the temporary Packer instance."
  default     = ""
}

variable "build_instance_type" {
  type        = string
  description = "x86_64 EC2 instance type used only during the AMI build."
  default     = "t3a.small"
}

variable "mysql_version" {
  type        = string
  description = "MySQL 8.4 LTS patch version installed in the image."
  default     = "8.4.11"
}

variable "node_exporter_version" {
  type        = string
  description = "Prometheus Node Exporter version installed in the image."
  default     = "1.12.1"
}

variable "mysqld_exporter_version" {
  type        = string
  description = "Prometheus MySQL Exporter version installed in the image."
  default     = "0.20.0"
}
