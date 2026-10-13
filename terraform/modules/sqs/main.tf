resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name_prefix}-document-jobs-dlq"
  message_retention_seconds = var.dlq_message_retention_seconds
  sqs_managed_sse_enabled   = true

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-document-jobs-dlq"
    Role = "dead-letter"
  })
}

resource "aws_sqs_queue" "jobs" {
  name                       = "${var.name_prefix}-document-jobs"
  visibility_timeout_seconds = var.visibility_timeout_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  message_retention_seconds  = var.message_retention_seconds
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-document-jobs"
    Role = "work"
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.jobs.arn]
  })
}

resource "aws_cloudwatch_metric_alarm" "dlq_visible_messages" {
  alarm_name          = "${var.name_prefix}-document-jobs-dlq-visible"
  alarm_description   = "At least one document job is visible in the DLQ."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }

  alarm_actions = var.alarm_action_arns
  ok_actions    = var.alarm_action_arns

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-document-jobs-dlq-visible"
  })
}

