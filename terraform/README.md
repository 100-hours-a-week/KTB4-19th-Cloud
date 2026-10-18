# Terraform

V2 AWS 인프라의 Terraform 원본을 관리한다.

## State 경계

- `bootstrap/`: 원격 State S3 Bucket
- `network/`: VPC, Subnet, IGW, NAT, Route Table, S3 Gateway Endpoint
- `shared/`: Route 53 Hosted Zone, 공용 ECR
- `monitoring/`: Private EC2 기반 Prometheus, Loki, Grafana
- `environments/staging/`: Staging 전용 자원
- `environments/prod/`: Production 전용 자원
- `modules/`: 환경에서 재사용하는 ECS, MySQL, AppConfig 등의 구성요소

초기에는 자동 Apply를 사용하지 않는다. 각 Root Module에서 `fmt`, `validate`, `plan` 결과를 확인한 뒤 승인된 변경만 단계적으로 적용한다.

AppConfig hosted configuration version을 여러 개 최초 생성할 때 AWS에서 동시 버전 번호 충돌(409)이 발생할 수 있다. 2026-10-16 prod의 잔여 생성은 `apply -parallelism=1 <검증한 plan>`으로 완료했다. 실패 후에는 전체 plan으로 남은 대상만 재검증하며, 실행 중인 설정을 초기화하거나 생성된 자원을 삭제해 재시도하지 않는다.

실제 Secret 값은 Terraform 변수나 State에 저장하지 않고 SSM Parameter Store에서 관리한다.

## Backend V2 GitHub OIDC

`shared/backend-oidc.tf`는 기존 V1 Role과 분리된 CI 1개·CD 2개 및 인라인 정책을 관리한다. 기존 GitHub OIDC Provider는 읽기 전용으로 참조한다. CI는 immutable 저장소 subject와 staging 브랜치, CD는 staging/production Environment subject를 정확히 일치시킨다. 기존 main 전용 V1 Role·Repository Variables는 변경하지 않는다.

| GitHub 등록 위치 | Variable | 값 |
| --- | --- | --- |
| Repository Actions Variables | `AWS_BACKEND_CI_V2_ROLE_ARN` | shared Output `backend_v2_delivery.ci_repository_variable.value` |
| Environment `staging` Variables | `AWS_BACKEND_CD_ROLE_ARN` | shared Output의 staging CD Role ARN |
| Environment `production` Variables | `AWS_BACKEND_CD_ROLE_ARN` | shared Output의 production CD Role ARN |

V2 CI 파일은 별도 변수명 `AWS_BACKEND_CI_V2_ROLE_ARN`을 사용한다. CD는 Environment별 동명 Variable이 기존 Repository Variable보다 우선 적용되는 방식이다. Environment Variable을 빼먹으면 기존 V1 Role로 잘못 인증을 시도할 수 있으므로 반드시 등록한다. Environment는 브랜치나 AWS 자원을 생성하지 않는다. 사용자 결정에 따라 추가 승인·대기 규칙은 사용하지 않는다. `workflow_run` CD의 기준 ref는 기본 브랜치일 수 있으므로 Environment 브랜치 제한을 코드의 staging 이미지 분기와 혼동하지 않는다.

CI는 Backend ECR Push/조회만, CD는 자기 환경의 API/Worker Service·Task Definition·PassRole 및 staging 검증 이력만 접근한다. prod CD는 검증 이력을 읽기만 한다. CD는 비밀번호 Parameter 조회·V1 SSM 명령 실행·ECR Push·Auto Scaling API 권한을 받지 않는다. `ecs:UpdateService` 권한 자체는 필드 단위로 Task 수 수정까지 막는 권한은 아니며, 현재 CD 코드가 Task 수를 전달하지 않는 관리 경계다. IAM Role을 사용할 수 있는 Workflow는 여전히 신뢰된 배포 코드여야 한다.

2026-10-16 shared plan 6개 생성·변경/삭제 0을 확인해 적용했다. 기존 shared 자원 14개 no-op, 후속 전체 plan No changes다. Access Analyzer identity policy 3개에서 finding이 없었고 IAM 시뮬레이션 28개 허용·차단 검사를 통과했다. Trust subject는 GitHub API의 owner/repository ID와 기존 V1 형식을 확인했으며 실제 GitHub OIDC Token으로 AssumeRole/배포한 검증은 별도로 남아 있다. GitHub Variables는 이 Terraform에서 등록하지 않는다.

ECS 애플리케이션 로그는 FireLens를 통해 Private Loki로 전달한다. 초기 Loki 인덱스 Label은 `environment`, `service`만 사용하며, JSON 로그의 `level` 등은 조회 시 파싱한다.

DB 접속정보와 Secret은 Parameter Store에서 주입한다. 마이그레이션 중 Writer, 읽기 비율, Outbox Worker 방향처럼 재배포 없이 바꿔야 하는 값은 AppConfig에서 관리한다.
