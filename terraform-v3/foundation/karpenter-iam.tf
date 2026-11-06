resource "aws_iam_role_policy" "karpenter_node_lifecycle" {
  name = "karpenter-node-lifecycle"
  role = aws_iam_role.addon["karpenter"].name

  # Based on the upstream v1.14.1 CloudFormation NodeLifecyclePolicy.
  policy = templatefile("${path.module}/policies/karpenter-node-lifecycle-v1.14.1.json.tftpl", {
    cluster_name = local.cluster_name
    region       = local.karpenter_region
  })
}

resource "aws_iam_role_policy" "karpenter_integrations" {
  name = "karpenter-integrations"
  role = aws_iam_role.addon["karpenter"].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AllowRegionalEC2Discovery"
      Effect   = "Allow"
      Resource = "*"
      Action = [
        "ec2:DescribeCapacityReservations",
        "ec2:DescribeImages",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeInstanceTypeOfferings",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribePlacementGroups",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSpotPriceHistory",
        "ec2:DescribeSubnets",
      ]
      Condition = { StringEquals = { "aws:RequestedRegion" = local.karpenter_region } }
      }, {
      Effect   = "Allow"
      Action   = ["pricing:GetProducts", "iam:ListInstanceProfiles"]
      Resource = "*"
      }, {
      Effect   = "Allow"
      Action   = "iam:GetInstanceProfile"
      Resource = aws_iam_instance_profile.karpenter_node.arn
      }, {
      Effect    = "Allow"
      Action    = "iam:PassRole"
      Resource  = aws_iam_role.eks_managed_node.arn
      Condition = { StringEquals = { "iam:PassedToService" = "ec2.amazonaws.com" } }
      }, {
      Effect   = "Allow"
      Action   = "eks:DescribeCluster"
      Resource = aws_eks_cluster.v3.arn
      }, {
      Effect   = "Allow"
      Action   = "ssm:GetParameter"
      Resource = "arn:aws:ssm:${local.karpenter_region}::parameter/aws/service/eks/optimized-ami/*"
      }, {
      Effect   = "Allow"
      Action   = ["sqs:GetQueueUrl", "sqs:ReceiveMessage", "sqs:DeleteMessage"]
      Resource = aws_sqs_queue.karpenter_interruption.arn
    }]
  })
}
