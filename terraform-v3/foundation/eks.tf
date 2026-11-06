locals {
  cluster_name = "zipsai-v3-eks"
  v3_tags = {
    Project   = "zipsai"
    Stack     = "v3"
    ManagedBy = "terraform"
  }
  eks_private_subnet_ids = {
    ap_northeast_2a = aws_subnet.v3_private_app_2a.id
    ap_northeast_2c = data.aws_subnet.shared["private_app_2c"].id
  }
}

data "aws_iam_policy_document" "eks_assume_role" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "${local.cluster_name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assume_role.json
  tags               = local.v3_tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_cloudwatch_log_group" "eks_control_plane" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = 30
  tags              = local.v3_tags
}

resource "aws_eks_cluster" "v3" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.36"
  tags     = local.v3_tags

  # The Cilium bootstrap workflow isolates aws-node before V3 nodes join.
  bootstrap_self_managed_addons = true

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  vpc_config {
    subnet_ids              = values(local.eks_private_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = false
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler",
  ]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster,
    aws_cloudwatch_log_group.eks_control_plane,
    aws_route.v3_private_app_2a_ipv4_default,
    aws_route_table_association.v3_private_app_2a,
  ]
}
