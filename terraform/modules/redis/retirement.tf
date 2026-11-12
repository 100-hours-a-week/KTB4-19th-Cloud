variable "enabled" {
  description = "Keep the legacy V2 Redis EC2 infrastructure enabled; V3 uses its own Kubernetes Redis."
  type        = bool
  default     = true
}

# Preserve resource identities when the legacy stack is enabled.
moved {
  from = aws_security_group.redis
  to   = aws_security_group.redis[0]
}

moved {
  from = aws_vpc_security_group_egress_rule.outbound
  to   = aws_vpc_security_group_egress_rule.outbound[0]
}

moved {
  from = aws_iam_role.instance
  to   = aws_iam_role.instance[0]
}

moved {
  from = aws_iam_role_policy_attachment.ssm
  to   = aws_iam_role_policy_attachment.ssm[0]
}

moved {
  from = aws_iam_role_policy.runtime
  to   = aws_iam_role_policy.runtime[0]
}

moved {
  from = aws_iam_instance_profile.redis
  to   = aws_iam_instance_profile.redis[0]
}

moved {
  from = aws_instance.redis
  to   = aws_instance.redis[0]
}

moved {
  from = aws_ssm_document.configure
  to   = aws_ssm_document.configure[0]
}

moved {
  from = aws_ssm_association.configure
  to   = aws_ssm_association.configure[0]
}

moved {
  from = aws_route53_record.redis
  to   = aws_route53_record.redis[0]
}
