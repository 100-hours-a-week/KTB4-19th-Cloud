# Frontend: private S3 and optional same-origin API

`api_origin_domain_name = null` preserves existing S3-only users, including Production.
Staging supplies `api-v2.zipsai.co.kr` as an HTTPS origin and enables these behaviors:

| Viewer path | Origin | Cache / request handling |
| --- | --- | --- |
| `/api`, `/api/*` | Staging ALB over HTTPS 443 | Managed-CachingDisabled (all TTLs zero), all methods, all query strings/cookies/viewer headers except Host, no compression |
| Other paths | Private frontend S3 through OAC | Existing static cache policy; viewer-request function rewrites extensionless SPA navigation to `/index.html` |

Authorization is forwarded by the managed all-viewer-except-Host policy. API paths are unchanged and the origin path is empty. API HTTP viewer requests are rejected rather than redirecting POST bodies. S3/SPA viewer requests redirect to HTTPS. The existing S3 public access block remains enabled.

Global 403/404-to-index.html mapping is not used with the API origin: API status/body must be preserved. Supported error response cache TTLs are zero. Missing `/assets/` and `/brand/` files are not rewritten to the SPA. Only the default S3 behavior has the SPA function; API behaviors never run it.

The origin read timeout is 60 seconds between response packets. Backend SSE heartbeat must remain shorter than that; this does not guarantee end-to-end SSE or model response correctness. ALB already has a 120-second idle timeout. Browser SSE, Cookie refresh, authentication and error-body handling require post-apply checks.

## Staging activation

The staging root enables custom domains. It requests a CloudFront certificate in us-east-1 and an ALB certificate in ap-northeast-2, creates DNS validation records and the `v2.zipsai.co.kr` / `api-v2.zipsai.co.kr` aliases, enables ALB HTTPS and redirects its HTTP listener to HTTPS. No Production/V1 DNS record is changed.

After apply, use `https://v2.zipsai.co.kr/api/actuator/health/readiness` or `https://api-v2.zipsai.co.kr/api/actuator/health/readiness`. Old raw ALB HTTP URLs redirect to that ALB hostname over HTTPS, which is not covered by the custom-domain certificate: do not use them for health checks or the previous port-forward login test. Update the Backend GitHub staging Environment `API_HEALTH_URL` separately; this code does not write GitHub Variables.

Frontend build files remain a separate deployment concern. Keep `index.html`, `assets/`, and `brand/` at the staging S3 root. No Frontend CI/CD is introduced here. S3 file contents are not managed or deleted by this module.

## Review / rollback

Review full staging and prod plans. Require no EC2/DB replacement, no V1 rules changed, no unintended ECS Task changes, and no prod differences. Staging API baseline is now 2 (Worker 0), matching the user's completed startup checks; re-plan after any console/power-script changes.

Rollback through a reviewed plan restoring the previous files: remove the optional API origin input and disable staging custom domains to return to S3-only CloudFront and HTTP ALB. This also removes staging aliases/certificates/HTTPS listener; it does not remove S3 objects. Restore GitHub health URLs only after the rollback completes. Never revert Production/V1 DNS for this staging rollback.
