# Add after v3.tfvars, managed-addons.tfvars, staging-nodes.tfvars and
# staging-ingress.tfvars. Keep staging access while enabling prod integration.
enable_v3_data_access       = true
v3_data_access_environments = ["staging", "prod"]
