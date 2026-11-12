# Keep the existing production DNS record in the V2 prod state during cutover.
variable "api_dns_target" {
  description = "Production API DNS destination: ecs for V2, eks for the V3 ALB."
  type        = string
  default     = "ecs"

  validation {
    condition     = contains(["ecs", "eks"], var.api_dns_target)
    error_message = "api_dns_target must be ecs or eks."
  }
}

# AWS Load Balancer Controller owns the ALB; Terraform only reads its endpoint.
data "aws_lb" "v3_production_api" {
  count = local.api_domain_enabled && var.api_dns_target == "eks" ? 1 : 0
  name  = "zipsai-v3-prod"
}
