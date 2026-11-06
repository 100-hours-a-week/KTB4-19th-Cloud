output "eks_cluster" {
  description = "V3 EKS control plane settings for node, add-on and access configuration."
  value = {
    name                      = aws_eks_cluster.v3.name
    version                   = aws_eks_cluster.v3.version
    endpoint                  = aws_eks_cluster.v3.endpoint
    cluster_security_group_id = aws_eks_cluster.v3.vpc_config[0].cluster_security_group_id
    private_subnet_ids        = local.eks_private_subnet_ids
  }
}
