output "bucket_name" {
  description = "Private Frontend origin bucket name."
  value       = aws_s3_bucket.frontend.id
}

output "bucket_arn" {
  description = "Private Frontend origin bucket ARN."
  value       = aws_s3_bucket.frontend.arn
}

output "distribution_id" {
  description = "CloudFront distribution ID."
  value       = aws_cloudfront_distribution.frontend.id
}

output "distribution_arn" {
  description = "CloudFront distribution ARN."
  value       = aws_cloudfront_distribution.frontend.arn
}

output "distribution_domain_name" {
  description = "CloudFront domain available before custom DNS cutover."
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "distribution_hosted_zone_id" {
  description = "CloudFront hosted zone ID used by Route 53 Alias records."
  value       = aws_cloudfront_distribution.frontend.hosted_zone_id
}
