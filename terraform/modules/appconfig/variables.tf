variable "name_prefix" {
  description = "Prefix used for AppConfig resources."
  type        = string
}

variable "environment" {
  description = "Application environment controlled by this AppConfig configuration."
  type        = string
}

variable "common_tags" {
  description = "Tags applied to AppConfig resources."
  type        = map(string)
}
