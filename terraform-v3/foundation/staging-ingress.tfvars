# Add to v3.tfvars + managed-addons.tfvars + staging-nodes.tfvars after
# Argo CD has created the zipsai-v3-staging ALB. Keep using this file thereafter.
v3_public_ingress_environments = ["staging"]
