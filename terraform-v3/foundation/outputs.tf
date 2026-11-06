output "shared_network" {
  description = "Existing network resources used by V3."
  value = {
    vpc_id          = data.aws_vpc.shared.id
    subnet_ids      = { for name, subnet in data.aws_subnet.shared : name => subnet.id }
    nat_gateway_id  = data.aws_nat_gateway.shared.id
    private_zone_id = data.aws_route53_zone.private.zone_id
  }
}

output "ecr_repositories" {
  description = "Existing image repository URLs and ARNs keyed by workload."
  value = {
    for name, repository in data.aws_ecr_repository.shared : name => {
      url = repository.repository_url
      arn = repository.arn
    }
  }
}

output "uploads_buckets" {
  description = "Existing upload buckets keyed by environment."
  value = {
    for environment, bucket in data.aws_s3_bucket.uploads : environment => {
      name = bucket.bucket
      arn  = bucket.arn
    }
  }
}

output "data_service_hosts" {
  description = "Existing private DNS names for MySQL and Qdrant."
  value = {
    for environment in keys(data.aws_s3_bucket.uploads) : environment => {
      mysql_primary = "mysql-primary.${environment}.${trimsuffix(data.aws_route53_zone.private.name, ".")}"
      qdrant        = "qdrant.${environment}.${trimsuffix(data.aws_route53_zone.private.name, ".")}"
    }
  }
}
