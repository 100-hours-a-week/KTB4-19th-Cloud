# 운영 DB 이관 관측 — 수집 기반 적용, 앱 배포 전

2026-10-18 운영 확인에서 Backend a050789는 실행 중이고 health 200이었지만 Prometheus endpoint는 노출 설정 누락으로 404였다. Agent는 Compose의 migration-control Profile에만 선언돼 실행되지 않았고, DB 이관 Worker 선언은 없었다. Prometheus에는 운영 앱 대상이 없었다. MySQL/Host 6개 수집 대상 UP과 앱 관측 준비 완료는 별개다.

## 개발과 운영의 차이

개발 API는 efd9d49, Migration Worker는 9b8cfa8이며 둘 다 실제 설정 계약인 MIGRATION_V2_DB_URL/USERNAME/PASSWORD와 MIGRATION_APPCONFIG_URL을 사용한다. 현재 운영 커밋 a050789의 application.properties도 같은 이름을 사용한다. 기존 DB_V2_*와 APPCONFIG_*만으로 해당 설정 바인딩이 완료됐다고 보지 않는다. 운영 API 이미지를 개발 이미지로 교체하지 않았다. 이관 Worker에는 별도 검증된 이미지 태그가 필요하다.

## 준비한 변경

- compose.yaml: Backend의 health,metrics,prometheus 노출 및 사설 IP 8080 바인딩. Agent를 기본 서비스로 준비한다.
- MIGRATION_V2_DB_URL은 기본 빈 값이다. V2 업무 DB 복원·검증 전에는 마이그레이션 기능을 활성화하지 않는다. 기존 V1 DB 경로와 API 이미지 태그는 유지한다.
- migration-worker는 별도 Profile이며 기본 CD로 실행되지 않는다. 별도 이미지 태그는 기본 pending으로 두어 운영자 선택 없이 이미지가 정해지지 않도록 했다. Worker는 닫기 스케줄러·Flyway를 비활성화하고 사설 8081만 사용한다. ECS 문서 처리 Worker와 다른 서비스다.
- Cloud CD: 기존 MIGRATION_V2_DB_URL·MIGRATION_WORKER_IMAGE_TAG를 보존한다. 실행 중인 이관 Worker가 있으면 파일 배포 전에 전체 CD를 중단해 remove-orphans의 영향을 방지한다. 일반 CD는 Worker를 실행하거나 AppConfig를 RUNNING으로 바꾸지 않는다.
- nginx/default.conf: 인터넷의 Prometheus·metrics 경로를 404로 차단한다. 내부 모니터링은 Nginx를 거치지 않고 사설 IP로 접근한다.
- monitoring/prometheus.yml: migration-application Job에 prod Backend/Worker 두 대상 추가. 기존 staging 대상은 유지한다. DB/Host의 V1 환경 라벨은 legacy-prod, 이관 앱은 prod이므로 대시보드 쿼리를 구분해야 한다.
- prod/migration-metrics.tf: 모니터링 SG에서 V1 8080~8081로만 접근하도록 하는 규칙이다. 공개 CIDR는 허용하지 않는다.

## 검증과 미적용 범위

Compose 기본·Worker Profile 구성 검증, Backend Migration 기본 비활성·Worker 기본 미기동 검사, CD YAML·셸·jq·생성 원격 셸 문법 검증을 통과했다. Nginx 실제 기동·promtool 런타임 검증과 운영 배포는 하지 않았다. Agent의 IMDS 조건은 운영 EC2의 IMDSv2 required·HopLimit 2를 읽기 전용으로 확인했다. 실제 AppConfig 수신은 배포 후 검증한다.

prod validate·plan은 SG 규칙 1 add·0 change·0 destroy다. monitoring validate는 통과했지만 전체 plan은 Prometheus Document/Association 2 update 외 기존 미적용 stack_config Document/Association 2 create도 포함한다. 사용자 기존 변경이므로 삭제하거나 전체 apply하지 않았다. 적용 전 이 범위를 따로 검토해야 한다. 어떤 Terraform apply·Cloud CD·컨테이너 기동도 이번 작업에서 실행하지 않았다.

### 후속 검토·적용 완료

위 내용은 최초 코드 준비 시점의 상태다. 이후 사용자 진행 요청으로 기존 스택의 실제 Compose·Loki·Grafana datasource 파일과 코드의 SHA-256을 대조해 세 파일 모두 같음을 확인했다. 미적용 두 자원은 동일한 기존 스택의 SSM 관리 등록이며, 검토 후 저장 plan을 적용했다. prod는 SG 1 added·0 changed·0 destroyed, monitoring은 2 added·2 changed·0 destroyed였다. 두 Root 모두 후속 plan No changes다.

기존 Prometheus·Grafana·Loki의 시작 시각은 각각 2026-10-13의 값으로 유지됐고 세 readiness가 정상이다. 기존 staging 앱 2개 및 운영 DB/Host 6개 대상은 UP을 유지했다. 새 prod 앱 대상 8080/8081은 V1 Cloud CD·Worker 기동 전이라 connection refused·DOWN이며, migration_*도 아직 없다. 수집 기반 적용과 실제 앱 수집 성공을 구분한다.

Backend main의 실제 backend-cd.yml은 .env의 BACKEND_IMAGE_TAG만 바꾸고 pull backend / up -d --no-deps backend를 실행한다. Compose·다른 변수·별도 Worker를 덮어쓰지 않아 이 작업에서 Backend CD 수정은 필요하지 않았다. Cloud CD 변경은 여전히 로컬 코드이며 커밋·push·실행하지 않았다. 운영 API 이미지도 변경하지 않았다.

적용 증빙은 작업 호스트 `/private/tmp/zipsai-50rps-precheck.2db4HO/`의 prod-app-metrics·monitoring-prod-app apply/post-plan 로그다. 스택 SSM `6c702cfd-5027-47ac-8da1-cb4fdc585ef2` Success, 최종 대상 점검 `5f293989-869c-41a2-b028-6075f69d29a6`, 실행 상태/health 점검 `906b39f9-ffe1-4b79-bdb8-6bb4c0fb1b32` Success다.

## 배포 순서

1. 준비한 코드와 기존 미적용 monitoring 스택의 영향을 검토한다. 운영 API 이미지와 Worker 호환성을 각각 확인한다.
2. 승인 후 SG·Prometheus 설정을 적용하고 Cloud CD로 Agent·Backend 관측을 반영한다. 단일 V1 Backend 재생성·Nginx 재시작 영향은 별도다.
3. Backend /prometheus 200·Agent prod Baseline 수신·Prometheus UP·외부 metrics 404를 확인한다. V2 URL이 비어 있으면 migration_* 없음이 정상일 수 있다.
4. V2 업무 DB 복원·GTID 추격 후 올바른 URL·검증 이미지 태그를 별도로 설정하고, prod AppConfig V1_PRIMARY/PAUSED·읽기/Shadow 0을 확인한 상태에서 이관 기능·Worker를 준비한다.
5. Worker 프로세스 실행과 이벤트 전달 활성화는 다르다. PAUSED에서 지표를 먼저 확인하고, GTID 채널 인계 기준을 충족한 뒤 RUNNING으로 바꾼다.

복사한 운영 Grafana 대시보드의 쿼리는 아직 별도 수정·검증이 필요하다. No data를 성공·0으로 해석하지 않는다. 계정·GTID·Dump·복제 상태는 이번 관측 코드가 변경하지 않는다.
