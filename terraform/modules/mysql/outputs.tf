output "instance_ids" {
  description = "MySQL EC2 instance IDs keyed by role."
  value       = { for role, instance in aws_instance.mysql : role => instance.id }
}

output "private_ips" {
  description = "MySQL private IP addresses keyed by role."
  value       = { for role, instance in aws_instance.mysql : role => instance.private_ip }
}

output "data_volume_ids" {
  description = "MySQL data EBS volume IDs keyed by role."
  value       = { for role, volume in aws_ebs_volume.data : role => volume.id }
}

output "security_group_id" {
  description = "Security group attached to both MySQL nodes."
  value       = aws_security_group.mysql.id
}

output "iam_role_name" {
  description = "IAM role used by MySQL EC2 instances."
  value       = aws_iam_role.mysql.name
}

