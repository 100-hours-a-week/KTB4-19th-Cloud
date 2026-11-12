# Apply only after api-v2 Host and the existing frontend CORS origin are ready in V3.
# Keep this file in subsequent staging applies; use -var=api_dns_target=ecs to roll back.
api_dns_target = "eks"
