# Use with v3.tfvars and managed-addons.tfvars after the Cilium bootstrap.
enable_eks_managed_node_groups = true
eks_managed_node_group_names   = ["staging-general", "observability"]

# Keep initial admin access until Argo CD and operator RBAC are verified.
enable_eks_bootstrap_admin = true
