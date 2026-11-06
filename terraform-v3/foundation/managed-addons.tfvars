# Pass explicitly after Cilium bootstrap, when creating the base node groups.
eks_managed_addon_versions = {
  coredns                = "v1.14.7-eksbuild.28"
  kube-proxy             = "v1.36.0-eksbuild.60"
  aws-ebs-csi-driver     = "v1.67.2-eksbuild.1"
  eks-pod-identity-agent = "v1.4.1-eksbuild.3"
}
