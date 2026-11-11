variable "v3_public_ingress_environments" {
  description = "Connect validation API DNS only after the corresponding Argo CD-managed ALB exists."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for environment in var.v3_public_ingress_environments : contains(["staging", "prod"], environment)])
    error_message = "Only staging and prod public ingress environments are supported."
  }
}

data "aws_route53_zone" "public" {
  count        = length(var.v3_public_ingress_environments) > 0 ? 1 : 0
  name         = "zipsai.co.kr."
  private_zone = false
}

# ALB lifecycle belongs to AWS Load Balancer Controller, not Terraform.
data "aws_lb" "public_ingress" {
  for_each = var.v3_public_ingress_environments
  name     = "zipsai-v3-${each.key}"
}

resource "aws_route53_record" "v3_api" {
  for_each = data.aws_lb.public_ingress
  zone_id  = data.aws_route53_zone.public[0].zone_id
  name     = "v3-${each.key}-api.zipsai.co.kr"
  type     = "A"

  alias {
    name                   = each.value.dns_name
    zone_id                = each.value.zone_id
    evaluate_target_health = true
  }
}

output "v3_public_api_urls" {
  value = { for environment, record in aws_route53_record.v3_api : environment => "https://${record.name}" }
}
