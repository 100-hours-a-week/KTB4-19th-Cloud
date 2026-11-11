variable "eks_operator_principal_arns" {
  description = "Existing IAM users or roles in this account allowed to assume the V3 EKS operator role."
  type        = set(string)

  validation {
    condition = length(var.eks_operator_principal_arns) > 0 && alltrue([
      for arn in var.eks_operator_principal_arns :
      can(regex("^arn:aws:iam::[0-9]{12}:(user|role)/[A-Za-z0-9+=,.@_/-]+$", arn))
    ])
    error_message = "Provide at least one exact IAM user or role ARN."
  }
}

variable "enable_eks_bootstrap_admin" {
  description = "Temporarily grant the operator role EKS cluster admin to install initial RBAC. Disable after verifying RBAC access."
  type        = bool
  default     = false
}

data "aws_ssm_parameter" "eks_management_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "eks_management" {
  name        = "${local.cluster_name}-management"
  description = "SSM-only EKS management host"
  vpc_id      = data.aws_vpc.shared.id
  tags        = local.v3_tags
}

resource "aws_vpc_security_group_egress_rule" "eks_management_https" {
  security_group_id = aws_security_group.eks_management.id
  description       = "HTTPS to EKS, SSM and tool repositories"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "eks_api_from_management" {
  security_group_id            = aws_eks_cluster.v3.vpc_config[0].cluster_security_group_id
  referenced_security_group_id = aws_security_group.eks_management.id
  description                  = "Private Kubernetes API from the SSM management host"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# The management host assumes the dedicated operator role for Kubernetes access.
resource "aws_iam_role" "eks_management" {
  name               = "${local.cluster_name}-management"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = local.v3_tags
}

resource "aws_iam_role_policy_attachment" "eks_management_ssm" {
  role       = aws_iam_role.eks_management.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "eks_management_operator" {
  name = "v3-eks-operator-assume"
  role = aws_iam_role.eks_management.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = aws_iam_role.eks_operator.arn
      },
      {
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = aws_eks_cluster.v3.arn
      },
    ]
  })
}

resource "aws_iam_instance_profile" "eks_management" {
  name = aws_iam_role.eks_management.name
  role = aws_iam_role.eks_management.name
  tags = local.v3_tags
}

resource "aws_instance" "eks_management" {
  ami                         = data.aws_ssm_parameter.eks_management_ami.value
  instance_type               = "t3a.micro"
  subnet_id                   = local.eks_private_subnet_ids.ap_northeast_2c
  vpc_security_group_ids      = [aws_security_group.eks_management.id]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.eks_management.name
  user_data                   = file("${path.module}/scripts/eks-management-user-data.sh")

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
  }

  tags = merge(local.v3_tags, {
    Name = "${local.cluster_name}-management"
  })

  depends_on = [aws_iam_role_policy_attachment.eks_management_ssm]
}

data "aws_iam_policy_document" "eks_operator_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = sort(concat(tolist(var.eks_operator_principal_arns), [aws_iam_role.eks_management.arn]))
    }
  }
}

resource "aws_iam_role" "eks_operator" {
  name               = "${local.cluster_name}-operator"
  assume_role_policy = data.aws_iam_policy_document.eks_operator_trust.json
  tags               = local.v3_tags

  lifecycle {
    precondition {
      condition = alltrue([
        for arn in var.eks_operator_principal_arns :
        startswith(arn, "arn:aws:iam::${data.aws_caller_identity.addon_account.account_id}:")
      ])
      error_message = "All operator principals must belong to the V3 AWS account."
    }
  }
}

data "aws_iam_policy_document" "eks_operator_access" {
  statement {
    sid       = "DescribeV3Cluster"
    actions   = ["eks:DescribeCluster"]
    resources = [aws_eks_cluster.v3.arn]
  }

  statement {
    sid     = "ConnectToManagementHost"
    actions = ["ssm:StartSession"]
    resources = [
      aws_instance.eks_management.arn,
      "arn:aws:ssm:ap-northeast-2:${data.aws_caller_identity.addon_account.account_id}:document/SSM-SessionManagerRunShell",
    ]
  }

  statement {
    sid       = "UseOwnSession"
    actions   = ["ssmmessages:OpenDataChannel", "ssm:ResumeSession", "ssm:TerminateSession"]
    resources = ["arn:aws:ssm:ap-northeast-2:${data.aws_caller_identity.addon_account.account_id}:session/&{aws:userid}-*"]
  }
}

resource "aws_iam_role_policy" "eks_operator_access" {
  name   = "v3-eks-operator-access"
  role   = aws_iam_role.eks_operator.name
  policy = data.aws_iam_policy_document.eks_operator_access.json
}

resource "aws_eks_access_entry" "platform_operator" {
  cluster_name      = aws_eks_cluster.v3.name
  principal_arn     = aws_iam_role.eks_operator.arn
  kubernetes_groups = ["platform-operators"]
  type              = "STANDARD"
  tags              = local.v3_tags
}

resource "aws_eks_access_policy_association" "bootstrap_admin" {
  count = var.enable_eks_bootstrap_admin ? 1 : 0

  cluster_name  = aws_eks_access_entry.platform_operator.cluster_name
  principal_arn = aws_eks_access_entry.platform_operator.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

output "eks_management_instance_id" {
  description = "Private EC2 instance ID to target with SSM Session Manager."
  value       = aws_instance.eks_management.id
}

output "eks_operator_role_arn" {
  description = "IAM role to assume for V3 EKS operations."
  value       = aws_iam_role.eks_operator.arn
}
