output "ecr_repository_urls" {
  description = "ECR Repository URLs keyed by service."
  value       = { for service, repository in aws_ecr_repository.service : service => repository.repository_url }
}

output "ecr_repository_arns" {
  description = "ECR Repository ARNs keyed by service."
  value       = { for service, repository in aws_ecr_repository.service : service => repository.arn }
}

output "route53_zone_id" {
  description = "Public Route 53 Hosted Zone ID for zipsai.co.kr."
  value       = aws_route53_zone.public.zone_id
}

output "route53_name_servers" {
  description = "Route 53 name servers to register at Gabia during the later DNS delegation step."
  value       = aws_route53_zone.public.name_servers
}

output "uploads_bucket_name" {
  description = "Existing Production upload bucket managed by the shared State."
  value       = aws_s3_bucket.uploads.id
}

output "uploads_bucket_arn" {
  description = "Existing Production upload bucket ARN."
  value       = aws_s3_bucket.uploads.arn
}

