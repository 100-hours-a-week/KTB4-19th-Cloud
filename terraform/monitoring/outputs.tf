output "instance_id" {
  description = "Monitoring EC2 instance ID used for SSM access."
  value       = module.monitoring.instance_id
}

output "private_ip" {
  description = "Monitoring EC2 private IP address."
  value       = module.monitoring.private_ip
}

output "loki_endpoint" {
  description = "Private Loki endpoint used by FireLens."
  value       = module.monitoring.loki_endpoint
}

output "grafana_port_forward_command" {
  description = "SSM command that exposes private Grafana on local port 3000."
  value       = "aws ssm start-session --target ${module.monitoring.instance_id} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"3000\"],\"localPortNumber\":[\"3000\"]}'"
}

output "prometheus_port_forward_command" {
  description = "SSM command that exposes private Prometheus on local port 9090."
  value       = "aws ssm start-session --target ${module.monitoring.instance_id} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"9090\"],\"localPortNumber\":[\"9090\"]}'"
}
