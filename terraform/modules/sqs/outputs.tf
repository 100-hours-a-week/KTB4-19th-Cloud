output "queue_name" {
  description = "Document jobs queue name."
  value       = aws_sqs_queue.jobs.name
}

output "queue_url" {
  description = "Document jobs queue URL used by the API and Worker."
  value       = aws_sqs_queue.jobs.url
}

output "queue_arn" {
  description = "Document jobs queue ARN used in ECS Task Role policies."
  value       = aws_sqs_queue.jobs.arn
}

output "dlq_name" {
  description = "Dead-letter queue name."
  value       = aws_sqs_queue.dlq.name
}

output "dlq_url" {
  description = "Dead-letter queue URL."
  value       = aws_sqs_queue.dlq.url
}

output "dlq_arn" {
  description = "Dead-letter queue ARN."
  value       = aws_sqs_queue.dlq.arn
}

output "dlq_alarm_arn" {
  description = "CloudWatch alarm ARN for visible DLQ messages."
  value       = aws_cloudwatch_metric_alarm.dlq_visible_messages.arn
}

