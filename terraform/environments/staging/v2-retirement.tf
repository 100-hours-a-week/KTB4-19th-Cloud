variable "enable_v2_apps" {
  description = "Keep legacy ECS, AI API, Embedding and Redis execution resources. Shared MySQL, Qdrant, frontend and networking remain enabled."
  type        = bool
  default     = true
  validation {
    condition     = var.enable_v2_apps || var.api_dns_target == "eks"
    error_message = "Retiring V2 apps requires the API DNS to point to the V3 ALB (api_dns_target=eks)."
  }
}

moved {
  from = aws_security_group.api_tasks
  to   = aws_security_group.api_tasks[0]
}

moved {
  from = aws_security_group.worker_tasks
  to   = aws_security_group.worker_tasks[0]
}

moved {
  from = aws_vpc_security_group_egress_rule.api_tasks_all_ipv4
  to   = aws_vpc_security_group_egress_rule.api_tasks_all_ipv4[0]
}

moved {
  from = aws_vpc_security_group_egress_rule.worker_tasks_all_ipv4
  to   = aws_vpc_security_group_egress_rule.worker_tasks_all_ipv4[0]
}
