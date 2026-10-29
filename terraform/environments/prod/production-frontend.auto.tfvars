# Keep enabled after the approved frontend TLS/CloudFront preparation.
# Apex DNS is owned separately by terraform/shared.
enable_production_frontend_domain = true

# Retired after CloudFront switched its /api origin to api.zipsai.co.kr.
enable_test_api_domain = false
