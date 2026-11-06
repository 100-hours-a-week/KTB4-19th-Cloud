variable "enable_eks_managed_node_groups" {
  description = "Create the baseline node groups after the bootstrap operator has restricted aws-node placement."
  type        = bool
  default     = false
}

locals {
  eks_managed_node_groups = {
    prod-general = {
      instance_type = "t3a.xlarge"
      node_count    = 3
      subnet_ids    = values(local.eks_private_subnet_ids)
      labels        = { environment = "prod", role = "general" }
    }
    staging-general = {
      instance_type = "t3a.xlarge"
      node_count    = 1
      subnet_ids    = values(local.eks_private_subnet_ids)
      labels        = { environment = "staging", role = "general" }
    }
    observability = {
      instance_type = "t3a.medium"
      node_count    = 1
      subnet_ids    = values(local.eks_private_subnet_ids)
      labels        = { role = "observability" }
    }
  }
}

resource "aws_iam_role" "eks_managed_node" {
  name               = "${local.cluster_name}-managed-node"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = local.v3_tags
}

resource "aws_iam_role_policy_attachment" "eks_managed_node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEC2ContainerRegistryPullOnly",
  ])

  role       = aws_iam_role.eks_managed_node.name
  policy_arn = "arn:aws:iam::aws:policy/${each.value}"
}

resource "aws_launch_template" "eks_managed_node" {
  name_prefix = "${local.cluster_name}-managed-node-"
  tags        = local.v3_tags

  credit_specification {
    cpu_credits = "standard"
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Set the Pod limit and register with the Cilium taint on the first kubelet join.
  user_data = base64encode(<<-MIME
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="NODEADM"

    --NODEADM
    Content-Type: application/node.eks.aws

    ---
    apiVersion: node.eks.aws/v1alpha1
    kind: NodeConfig
    spec:
      kubelet:
        flags:
          - --max-pods=16
          - --register-with-taints=node.cilium.io/agent-not-ready=true:NoExecute
        config:
          maxPods: 16
    --NODEADM--
  MIME
  )
}

resource "aws_eks_node_group" "baseline" {
  for_each = var.enable_eks_managed_node_groups ? local.eks_managed_node_groups : {}

  cluster_name    = aws_eks_cluster.v3.name
  node_group_name = each.key
  node_role_arn   = aws_iam_role.eks_managed_node.arn
  subnet_ids      = each.value.subnet_ids
  ami_type        = "AL2023_x86_64_STANDARD"
  capacity_type   = "ON_DEMAND"
  instance_types  = [each.value.instance_type]
  labels          = each.value.labels
  tags            = local.v3_tags

  launch_template {
    id      = aws_launch_template.eks_managed_node.id
    version = tostring(aws_launch_template.eks_managed_node.latest_version)
  }

  scaling_config {
    min_size     = each.value.node_count
    max_size     = each.value.node_count
    desired_size = each.value.node_count
  }

  update_config {
    max_unavailable = 1
  }

  # Cilium removes the startup taint after initializing the node.
  taint {
    key    = "node.cilium.io/agent-not-ready"
    value  = "true"
    effect = "NO_EXECUTE"
  }

  dynamic "taint" {
    for_each = each.key == "observability" ? [true] : []

    content {
      key    = "role"
      value  = "observability"
      effect = "NO_SCHEDULE"
    }
  }

  depends_on = [aws_iam_role_policy_attachment.eks_managed_node]
}
