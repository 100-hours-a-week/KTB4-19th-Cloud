# V2 ALB 액세스 로그

**2026-10-20 적용 상태:** 사용자 추가 승인 후 AWS 표준 ALB 로그 전달 서비스 + 계정 ID 경로 제한 정책으로 수정했다. 양 환경의 저장 plan 적용이 각각 0 add·2 change·0 destroy로 완료됐고, 실제 ALB access_logs enabled=true 및 bucket/prefix, S3 쓰기 검사 파일 생성, readiness 200을 확인했다. 전용 버킷·공개 차단·AES256·14일 만료 규칙을 유지한다. V1·ECS·DB·Frontend는 변경하지 않았다. 앞선 특정 ALB SourceArn 제한 정책은 권한 검사에서 실패했으며 승인된 변경으로 해결됐다.

공용 ECS 모듈이 환경별 전용 S3 버킷과 ALB access_logs 속성을 관리한다. V1·Frontend 버킷·Loki 수집 설정은 변경하지 않는다.

| 환경 | 버킷 | Prefix |
| --- | --- | --- |
| staging | zipsai-staging-alb-access-929368845727 | alb/ |
| prod | zipsai-prod-alb-access-929368845727 | alb/ |

S3 콘솔에서 `alb/AWSLogs/<account-id>/elasticloadbalancing/ap-northeast-2/YYYY/MM/DD/`를 열고 필요한 `.log.gz`를 다운로드·압축 해제한다. 날짜와 로그의 시간은 UTC이므로 한국 시간에서 9시간을 뺀다. 요청 IP:port, URL, User-Agent, ALB 상태 코드와 target 상태 코드를 같은 시간대로 대조한다. IP·전체 URL에는 개인정보가 포함될 수 있어 원문을 공개 채팅에 공유하지 않는다. IP만으로 실제 사람이나 공격 여부를 확정하지 않는다. 앞단 프록시를 경유한 경우 client IP는 프록시일 수 있다.

- 전용 버킷의 공개 접근은 전부 차단한다. 읽기용 IAM 권한을 새로 팀원에게 부여하지 않는다.
- SSE-S3(AES256)와 BucketOwnerEnforced를 사용한다. AWS 표준 전달 정책에 따라 ALB 로그 전달 서비스에 지정 버킷의 `alb/AWSLogs/929368845727/*` PutObject만 허용한다. 다른 계정의 로그 경로·GetObject·삭제 권한이나 공개 접근은 허용하지 않는다. 특정 ALB ARN으로는 제한하지 않으므로 같은 계정의 다른 ALB도 이 경로로 로그를 보내도록 설정할 수 있다. 일반 주체의 비 TLS 접근은 차단하고 AWS 서비스는 전송 메타데이터 생략에 따른 거부를 피하도록 이 Deny에서 제외한다.
- 버전 관리는 활성화하지 않는다. `alb/` 객체는 생성 후 14일 만료 규칙으로 삭제한다. S3의 UTC 날짜 계산·비동기 처리 때문에 정확히 생성 336시간 후 삭제된다는 보장은 없다. 미완료 multipart upload는 1일 후 정리한다.
- 만료로 삭제된 로그는 이 버킷에서 복구할 수 없다. 별도 보존이 필요하면 만료 전에 승인된 위치로 내보낸다.
- 로그는 소급 생성되지 않고 즉시 실시간으로 도착하지 않는다. `ELBAccessLogTestFile`은 쓰기 권한 검사 결과이지 실제 요청 로그가 아니다.
- ALB access log는 best-effort이며 완전한 감사 원장이 아니다. Grafana/Loki·Athena 연결은 이번 범위에 포함하지 않는다.
- S3 저장·요청·다운로드 비용이 발생할 수 있다.

검증은 ALB 속성 enabled/bucket/prefix, S3 lifecycle 14일, public access block, encryption, 실제 `.log.gz` 도착 및 readiness 응답을 구분해 확인한다. Terraform 전체 plan에 ALB DNS 의존성으로 Frontend data source 재조회가 연쇄되면 전체 plan 검토 후 ALB와 로그 자원만 한정한 저장 plan을 사용하고, 적용 후 전체 plan으로 잔여 변경을 확인한다.

복구 시 IaC에서 ALB access_logs.enabled를 false로 변경해 먼저 적용한다. 버킷은 남겨 기존 보관 주기를 유지하며, 비어 있지 않은 버킷은 force_destroy=false로 보호한다. 로그 중단 전에 버킷을 제거하지 않는다.

근거: [AWS ALB 액세스 로그 설정](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-access-logging.html), [S3 객체 만료 동작](https://docs.aws.amazon.com/AmazonS3/latest/userguide/lifecycle-expire-general-considerations.html).
