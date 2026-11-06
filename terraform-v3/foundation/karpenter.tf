locals {
  karpenter_region = "ap-northeast-2"
  karpenter_name   = "${local.cluster_name}-karpenter"
  karpenter_interruption_events = {
    scheduled-change     = { source = "aws.health", type = "AWS Health Event" }
    spot-interruption    = { source = "aws.ec2", type = "EC2 Spot Instance Interruption Warning" }
    rebalance            = { source = "aws.ec2", type = "EC2 Instance Rebalance Recommendation" }
    instance-state       = { source = "aws.ec2", type = "EC2 Instance State-change Notification" }
    capacity-reservation = { source = "aws.ec2", type = "EC2 Capacity Reservation Instance Interruption Warning" }
  }
}

# Karpenter shares the MNG node role and the Access Entry created by EKS for it.
resource "aws_iam_instance_profile" "karpenter_node" {
  name = local.karpenter_name
  role = aws_iam_role.eks_managed_node.name
  tags = local.v3_tags
}

resource "aws_sqs_queue" "karpenter_interruption" {
  name                      = local.karpenter_name
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
  tags                      = local.v3_tags
}

resource "aws_cloudwatch_event_rule" "karpenter_interruption" {
  for_each = local.karpenter_interruption_events

  name = "${local.karpenter_name}-${each.key}"
  event_pattern = jsonencode({
    source        = [each.value.source]
    "detail-type" = [each.value.type]
  })
  tags = local.v3_tags
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.url
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowInterruptionEvents"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.karpenter_interruption.arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = [for rule in aws_cloudwatch_event_rule.karpenter_interruption : rule.arn] }
      }
      }, {
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "sqs:*"
      Resource  = aws_sqs_queue.karpenter_interruption.arn
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

resource "aws_cloudwatch_event_target" "karpenter_interruption" {
  for_each = aws_cloudwatch_event_rule.karpenter_interruption

  rule      = each.value.name
  target_id = "karpenter-interruption-queue"
  arn       = aws_sqs_queue.karpenter_interruption.arn

  depends_on = [aws_sqs_queue_policy.karpenter_interruption]
}

data "aws_security_group" "karpenter_ssm_endpoint" {
  vpc_id = data.aws_vpc.shared.id
  tags   = { Name = "zipsai-shared-ssm-endpoints-sg" }
}

# The shared VPC's private SSM DNS resolves to this endpoint in both AZs.
resource "aws_vpc_security_group_ingress_rule" "karpenter_ssm_endpoint" {
  security_group_id            = data.aws_security_group.karpenter_ssm_endpoint.id
  referenced_security_group_id = aws_eks_cluster.v3.vpc_config[0].cluster_security_group_id
  description                  = "HTTPS from V3 EKS nodes and pods to SSM"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  tags                         = local.v3_tags
}
