data "aws_caller_identity" "addon_account" {}

locals {
  addon_identities = {
    cilium = {
      name            = "cilium-operator"
      namespace       = "kube-system"
      service_account = "cilium-operator"
    }
    ebs_csi = {
      name            = "ebs-csi-controller"
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
    }
    alb = {
      name            = "aws-load-balancer-controller"
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
    karpenter = {
      name            = "karpenter-controller"
      namespace       = "karpenter"
      service_account = "karpenter"
    }
    eso = {
      name            = "external-secrets"
      namespace       = "external-secrets"
      service_account = "external-secrets"
    }
  }
}

resource "aws_iam_role" "addon" {
  for_each = local.addon_identities

  name = "v3-${each.value.name}-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals = {
          "aws:RequestTag/eks-cluster-arn"            = aws_eks_cluster.v3.arn
          "aws:RequestTag/kubernetes-namespace"       = each.value.namespace
          "aws:RequestTag/kubernetes-service-account" = each.value.service_account
        }
      }
    }]
  })
  tags = local.v3_tags
}

resource "aws_iam_role_policy" "cilium_eni" {
  name = "cilium-eni-ipam"
  role = aws_iam_role.addon["cilium"].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeRouteTables",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets",
        "ec2:DescribeTags",
        "ec2:DescribeVpcs",
        "ec2:CreateNetworkInterface",
        "ec2:AttachNetworkInterface",
        "ec2:ModifyNetworkInterfaceAttribute",
        "ec2:DeleteNetworkInterface",
        "ec2:AssignPrivateIpAddresses",
        "ec2:CreateTags",
      ]
      Resource  = "*"
      Condition = { StringEquals = { "aws:RequestedRegion" = "ap-northeast-2" } }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.addon["ebs_csi"].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicyV2"
}

resource "aws_iam_role_policy" "alb_controller" {
  name = "aws-load-balancer-controller-v3-6-2"
  role = aws_iam_role.addon["alb"].name
  # Upstream kubernetes-sigs/aws-load-balancer-controller v3.6.2 docs/install/iam_policy.json.
  policy = file("${path.module}/policies/aws-load-balancer-controller-v3.6.2.json")
}

resource "aws_iam_role_policy" "external_secrets" {
  name = "v3-parameter-reader-assume"
  role = aws_iam_role.addon["eso"].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sts:AssumeRole", "sts:TagSession"]
      Resource = [for role in aws_iam_role.parameter_reader : role.arn]
    }]
  })
}

# The EKS add-on owns the EBS CSI association.
resource "aws_eks_pod_identity_association" "addon" {
  for_each = { for key, identity in local.addon_identities : key => identity if key != "ebs_csi" }

  cluster_name    = aws_eks_cluster.v3.name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = aws_iam_role.addon[each.key].arn
  tags            = local.v3_tags

  depends_on = [
    aws_iam_role_policy.cilium_eni,
    aws_iam_role_policy.alb_controller,
    aws_iam_role_policy.external_secrets,
  ]
}
