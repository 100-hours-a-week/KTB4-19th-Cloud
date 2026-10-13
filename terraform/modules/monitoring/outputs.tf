output "instance_id" {
  description = "Monitoring EC2 instance ID."
  value       = aws_instance.monitoring.id
}

output "private_ip" {
  description = "Monitoring EC2 private IP address."
  value       = aws_instance.monitoring.private_ip
}

output "loki_endpoint" {
  description = "Private Loki endpoint used by FireLens."
  value       = "loki.monitoring.zipsai.internal:3100"
}

output "data_volume_id" {
  description = "Persistent monitoring EBS volume ID."
  value       = aws_ebs_volume.data.id
}
