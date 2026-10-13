output "vpc_id" {
  description = "ID of the shared Zipsai VPC."
  value       = aws_vpc.zipsai.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the shared Zipsai VPC."
  value       = aws_vpc.zipsai.cidr_block
}

output "public_subnet_2c_id" {
  description = "ID of the existing public subnet in ap-northeast-2c."
  value       = aws_subnet.public_2c.id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway attached to the shared VPC."
  value       = aws_internet_gateway.zipsai.id
}

output "public_route_table_id" {
  description = "ID of the existing public route table."
  value       = aws_route_table.public.id
}

output "public_subnet_2a_id" {
  description = "ID of the public subnet in ap-northeast-2a."
  value       = aws_subnet.public_2a.id
}

output "private_app_subnet_2c_id" {
  description = "ID of the private application subnet in ap-northeast-2c."
  value       = aws_subnet.private_app_2c.id
}

output "private_data_subnet_ids" {
  description = "Private data subnet IDs keyed by Availability Zone."
  value = {
    ap_northeast_2a = aws_subnet.private_data_2a.id
    ap_northeast_2c = aws_subnet.private_data_2c.id
  }
}

output "private_app_route_table_id" {
  description = "ID of the private application route table."
  value       = aws_route_table.private_app.id
}

output "private_data_route_table_id" {
  description = "ID of the isolated private data route table."
  value       = aws_route_table.private_data.id
}

output "nat_gateway_id" {
  description = "ID of the single NAT Gateway in ap-northeast-2c."
  value       = aws_nat_gateway.app_2c.id
}

output "s3_gateway_endpoint_id" {
  description = "ID of the S3 Gateway VPC Endpoint."
  value       = aws_vpc_endpoint.s3.id
}

output "ssm_interface_endpoint_ids" {
  description = "IDs of the SSM-related Interface VPC Endpoints."
  value       = { for service, endpoint in aws_vpc_endpoint.ssm : service => endpoint.id }
}

output "private_dns_zone_id" {
  description = "Route 53 private hosted zone used for stable internal service names."
  value       = aws_route53_zone.private.zone_id
}

output "private_dns_zone_name" {
  description = "Route 53 private hosted zone name."
  value       = aws_route53_zone.private.name
}

output "monitoring_client_security_group_id" {
  description = "Security group attached to workloads that send logs to Loki."
  value       = aws_security_group.monitoring_clients.id
}

output "monitoring_server_security_group_id" {
  description = "Security group attached to the private monitoring server."
  value       = aws_security_group.monitoring_server.id
}
