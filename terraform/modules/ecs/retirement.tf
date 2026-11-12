variable "enabled" {
  description = "Keep V2 ECS application infrastructure enabled; disable after V3 cutover. Existing ALB log archives are retained."
  type        = bool
  default     = true
}

# Preserve resource identities when the legacy stack is enabled.
moved {
  from = aws_iam_role.execution
  to   = aws_iam_role.execution[0]
}

moved {
  from = aws_iam_role_policy_attachment.execution
  to   = aws_iam_role_policy_attachment.execution[0]
}

moved {
  from = aws_iam_role.api_task
  to   = aws_iam_role.api_task[0]
}

moved {
  from = aws_iam_role_policy.api_task
  to   = aws_iam_role_policy.api_task[0]
}

moved {
  from = aws_iam_role.worker_task
  to   = aws_iam_role.worker_task[0]
}

moved {
  from = aws_iam_role_policy.worker_task
  to   = aws_iam_role_policy.worker_task[0]
}

moved {
  from = aws_ecs_cluster.this
  to   = aws_ecs_cluster.this[0]
}

moved {
  from = aws_ecs_task_definition.api
  to   = aws_ecs_task_definition.api[0]
}

moved {
  from = aws_ecs_task_definition.worker
  to   = aws_ecs_task_definition.worker[0]
}

moved {
  from = aws_security_group.alb
  to   = aws_security_group.alb[0]
}

moved {
  from = aws_vpc_security_group_ingress_rule.alb_http
  to   = aws_vpc_security_group_ingress_rule.alb_http[0]
}

moved {
  from = aws_vpc_security_group_egress_rule.alb_to_api
  to   = aws_vpc_security_group_egress_rule.alb_to_api[0]
}

moved {
  from = aws_vpc_security_group_ingress_rule.api_from_alb
  to   = aws_vpc_security_group_ingress_rule.api_from_alb[0]
}

moved {
  from = aws_lb.api
  to   = aws_lb.api[0]
}

moved {
  from = aws_lb_target_group.api
  to   = aws_lb_target_group.api[0]
}

moved {
  from = aws_lb_listener.http
  to   = aws_lb_listener.http[0]
}

moved {
  from = aws_ecs_service.api
  to   = aws_ecs_service.api[0]
}

moved {
  from = aws_ecs_service.worker
  to   = aws_ecs_service.worker[0]
}

moved {
  from = aws_ssm_parameter.deployment_contract
  to   = aws_ssm_parameter.deployment_contract[0]
}
