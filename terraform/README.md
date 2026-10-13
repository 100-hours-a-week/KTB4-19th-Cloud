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

실제 Secret 값은 Terraform 변수나 State에 저장하지 않고 SSM Parameter Store에서 관리한다.

ECS 애플리케이션 로그는 FireLens를 통해 Private Loki로 전달한다. 초기 Loki 인덱스 Label은 `environment`, `service`만 사용하며, JSON 로그의 `level` 등은 조회 시 파싱한다.

DB 접속정보와 Secret은 Parameter Store에서 주입한다. 마이그레이션 중 Writer, 읽기 비율, Outbox Worker 방향처럼 재배포 없이 바꿔야 하는 값은 AppConfig에서 관리한다.
