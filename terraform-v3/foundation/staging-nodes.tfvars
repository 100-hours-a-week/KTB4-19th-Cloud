# Use with v3.tfvars and managed-addons.tfvars after the Cilium bootstrap.
enable_eks_managed_node_groups = true
eks_managed_node_group_names   = ["staging-general", "observability", "observability-2a"]

# Keep initial admin access until Argo CD and operator RBAC are verified.
enable_eks_bootstrap_admin = true

# Allow room for system Pods, Argo CD and common controllers.
eks_managed_node_max_pods = 32

# Allow integration with staging data services only; keep prod access closed.
enable_v3_data_access       = true
v3_data_access_environments = ["staging"]

# Migration: keep observability until EBS attachment and monitoring on observability-2a are verified.
