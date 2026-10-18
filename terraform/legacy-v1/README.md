# V1 자원 Import

현재 운영·개발 서버를 기존 설정 그대로 별도 `legacy-v1` State에 편입하기 위한 Root다. V2 환경 신규 배포나 V1 종료 작업이 아니다.

## 관리 경계

| 대상 | 관리 위치 |
| --- | --- |
| V1 운영·개발 EC2, 각 Root·Data EBS 설정 | 이 Root의 `aws_instance`와 block device 설정. EBS를 별도 Resource로 중복 관리하지 않음 |
| V1 SG 자체와 아직 다른 State에 없는 HTTP·HTTPS·Egress 규칙 | 이 Root. SG inline ingress/egress를 선언하지 않음 |
| V1 IAM Role·Instance Profile·정책 연결, 개발 Observability·S3 inline 정책 | 이 Root. Role의 정책 전체를 배타적으로 관리하지 않음 |
| 운영 EIP·연결 | 이 Root. 주소 할당과 연결 관리를 분리 |
| 공용 VPC·Subnet·경로, 운영 SG의 Exporter 규칙 | 기존 network State 유지 |
| DNS·ECR·운영 Upload S3 | 기존 shared State 유지 |
| 개발 SG의 MySQL·Exporter 규칙, AppConfig·Parameter 읽기 inline 정책 | 기존 staging State 유지 |

기존 AWS Managed Policy와 고객 관리형 Policy의 **연결**만 편입하며, 정책 정의 자체는 이번 대상이 아니다. 나머지 V1 S3 Bucket은 사용처·관리 주체 확인 후 별도 검토한다. 따라서 이 Root의 검증을 V1 전체 자원의 편입 완료로 해석하지 않는다.

운영 Data EBS는 `delete_on_termination=false`, 개발 Data EBS는 현재 값인 `true`를 유지한다. 모든 편입 Resource에는 `prevent_destroy`를 두지만, 이 설정은 콘솔 삭제나 코드 제거까지 차단하지 않는다. 기존 user data는 저장소로 복사하지 않으며 Import 과정에서 변경하지 않는다. 애플리케이션·스케줄러 설정은 수정하지 않는다.

## 실행 경계

```sh
AWS_PROFILE=terraform terraform init
terraform fmt -check
AWS_PROFILE=terraform terraform validate
AWS_PROFILE=terraform terraform plan -out=/private/tmp/zipsai-v1-reviewed.tfplan
```

최초 편입 plan의 기대 결과는 **25 import, 0 add, 0 change, 0 destroy**이며, 편입 후에는 **No changes**여야 한다. plan 단계에서는 State에 실제 편입되지 않는다. plan 파일은 민감 정보를 포함할 수 있으므로 저장소에 추가하거나 문서에 원문을 복사하지 않는다.

실제 Import 전에는 다른 관리 도구의 소유권을 확인한다. 기존 V1의 Terraform 태그만으로 현재 관리 주체를 확정하지 않는다. 승인 후 새 plan을 검토하고 apply해야 하며, 변경·교체·삭제가 포함되면 중단한다. apply 후에는 다시 변경 0과 서버·서비스 상태를 확인한다.

## 적용 기록 — 2026-10-16

사용자 요청에 따라 새 Import-only plan을 검토하고 적용했다. **25 imported, 0 added, 0 changed, 0 destroyed**이며, 별도 `legacy-v1` State에 편입했다. 이후 plan은 종료 코드 0·No changes였다. 기존 S3 backend의 버전 관리가 Enabled임을 확인했다.

두 서버의 실행 상태·SG 연결·IAM Profile·Private/Public IP와 SG 전체 규칙을 전후 대조해 변경 없음을 확인했다. SSM 에이전트도 두 서버 모두 Online이며, 고정 문자열 출력 명령을 두 서버에서 실행해 모두 Success·종료 코드 0을 확인했다. Redis·Valkey·스케줄러·DNS 및 다른 Root는 적용하지 않았다.

검증 파일은 접근 제한 임시 경로 `/private/tmp/zipsai-v1-import-final.U3sU66`에 보관했다. 자원 삭제는 완전 이관과 복귀 기간 종료를 확인한 다음 별도 plan으로 검토한다.

## V1 모니터링 관리 — 2026-10-18

`exporters.tf`의 SSM Document·Association으로 V1 개발·운영 Exporter를 관리한다. `exporters.auto.tfvars`에 양 환경 활성화를 유지한다. 인프라 편입 이후 추가한 모니터링 기능이며 기존 서비스 Compose·이미지를 배포하지 않는다.

개발 단계는 Document 1개·Association 1개 생성, 운영 단계는 Association 1개 생성만 적용했다. 기존 계정·파일·컨테이너가 있으면 검증 후 보존하며 운영에는 전용 모니터링 계정·파일과 별도 Compose 프로젝트의 Exporter 두 개를 추가했다. Prometheus의 운영 9100·9104 두 대상 UP·mysql_up=1, 기존 서비스 ID·기동 시각과 MySQL 전역 설정 유지, 후속 전체 plan No changes를 확인했다.

실행·실패·복구 경계는 `runbooks/monitoring/v1-exporters.md`를 따른다. 활성화 변수를 끄거나 Association을 제거해도 서버 계정·파일·Exporter가 자동 삭제되지는 않는다.
