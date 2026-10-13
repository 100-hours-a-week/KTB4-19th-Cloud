variable "name_prefix" {
  description = "Prefix used for MySQL resource names."
  type        = string
}

variable "common_tags" {
  description = "Tags applied to all MySQL resources."
  type        = map(string)
}

variable "vpc_id" {
  description = "VPC containing the database nodes."
  type        = string
}

variable "vpc_cidr_block" {
  description = "VPC CIDR used for private endpoint and DNS egress."
  type        = string
}

variable "client_security_group_ids" {
  description = "Security groups allowed to connect to MySQL."
  type        = map(string)
  default     = {}
}

variable "monitoring_security_group_id" {
  description = "Security group allowed to scrape Node and MySQL Exporter metrics."
  type        = string
}

variable "secret_parameter_arns" {
  description = "SSM Parameter ARNs that the MySQL nodes may read during initialization and operation."
  type        = set(string)
}

variable "ami_id" {
  description = "Packer-built Ubuntu MySQL AMI ID."
  type        = string

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID."
  }
}

variable "instance_type" {
  description = "EC2 instance type used by Primary and Replica."
  type        = string
  default     = "t3a.small"
}

variable "primary_subnet_id" {
  description = "Private data subnet ID for the Primary."
  type        = string
}

variable "primary_availability_zone" {
  description = "Availability Zone for the Primary."
  type        = string
  default     = "ap-northeast-2c"
}

variable "replica_subnet_id" {
  description = "Private data subnet ID for the Replica."
  type        = string
}

variable "replica_availability_zone" {
  description = "Availability Zone for the Replica."
  type        = string
  default     = "ap-northeast-2a"
}

variable "root_volume_size_gib" {
  description = "Encrypted root volume size for each database node."
  type        = number
  default     = 12
}

variable "data_volume_size_gib" {
  description = "Encrypted gp3 data volume size for each database node."
  type        = number
  default     = 20
}

variable "data_volume_iops" {
  description = "Provisioned IOPS for each gp3 data volume."
  type        = number
  default     = 3000
}

variable "data_volume_throughput" {
  description = "Provisioned throughput in MiB/s for each gp3 data volume."
  type        = number
  default     = 125
}

variable "kms_key_id" {
  description = "Optional customer-managed KMS key. Null uses the AWS managed EBS key."
  type        = string
  default     = null
}
