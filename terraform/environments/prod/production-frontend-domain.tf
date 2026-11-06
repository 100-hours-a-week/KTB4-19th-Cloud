variable "enable_production_frontend_domain" {
  description = "Prepare production frontend TLS/CloudFront aliases without changing the apex DNS owned by shared State."
  type        = bool
  default     = false
}

# Hand off only the shared apex/wildcard validation CNAME without deleting it.
# The former www validation record is not moved and is removed normally.
# Apply prod first, then apply shared's import. See runbooks/shared-acm-migration.md.
moved {
  from = aws_route53_record.production_frontend_certificate_validation["zipsai.co.kr"]
  to   = aws_route53_record.shared_certificate_validation_handoff
}

removed {
  from = aws_route53_record.shared_certificate_validation_handoff
  lifecycle {
    destroy = false
  }
}
