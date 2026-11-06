variable "eks_managed_addon_versions" {
  description = "EKS 1.36-compatible add-on versions verified in ap-northeast-2. Null leaves managed add-ons disabled."
  type = object({
    coredns                = string
    kube-proxy             = string
    aws-ebs-csi-driver     = string
    eks-pod-identity-agent = string
  })
  default = null

  validation {
    condition = var.eks_managed_addon_versions == null ? true : alltrue([
      for version in var.eks_managed_addon_versions : can(regex("^v[0-9]+[.][0-9]+[.][0-9]+-eksbuild[.][0-9]+$", version))
    ])
    error_message = "Pin all four managed add-ons to an explicit vX.Y.Z-eksbuild.N version."
  }
}

resource "aws_eks_addon" "managed" {
  for_each = var.eks_managed_addon_versions == null ? {} : tomap(var.eks_managed_addon_versions)

  cluster_name  = aws_eks_cluster.v3.name
  addon_name    = each.key
  addon_version = each.value

  # CoreDNS and kube-proxy are initially bootstrapped as self-managed components.
  resolve_conflicts_on_create = contains(["coredns", "kube-proxy"], each.key) ? "OVERWRITE" : "NONE"
  resolve_conflicts_on_update = "PRESERVE"
  tags                        = local.v3_tags

  dynamic "pod_identity_association" {
    for_each = each.key == "aws-ebs-csi-driver" ? [local.addon_identities.ebs_csi.service_account] : []

    content {
      service_account = pod_identity_association.value
      role_arn        = aws_iam_role.addon["ebs_csi"].arn
    }
  }

  depends_on = [aws_iam_role_policy_attachment.ebs_csi]
}
