# Add after v3.tfvars, managed-addons.tfvars, staging-nodes.tfvars,
# staging-ingress.tfvars and prod-data-access.tfvars.
# Preserve existing baseline groups and add three prod-general nodes.
eks_managed_node_group_names = ["staging-general", "observability-2a", "prod-general"]
