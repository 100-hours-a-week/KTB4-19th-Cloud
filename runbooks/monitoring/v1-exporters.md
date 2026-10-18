# V1 Exporter 구성·검증

V1의 기존 Docker MySQL·Backend·Nginx·AI를 유지하고 모니터링만 관리한다. 기존 CloudWatch 수집과 서비스 Compose는 수정하지 않는다.

## 1. 관리 경계

`terraform/legacy-v1/exporters.tf`가 SSM Document와 환경별 Association을 관리한다. 서버 설정은 `terraform/modules/mysql/scripts/configure_v1_exporters.py`가 수행하며, V2 스크립트의 IMDSv2·SigV4 Parameter 조회와 비밀번호 파싱·SQL 이스케이프를 재사용한다.

| 대상 | 처리 |
|---|---|
| 기존 모니터링 계정·파일 | 값·권한이 맞으면 보존, 다르면 중단. 비밀번호 회전·권한 재설정 없음 |
| 신규 계정 | `mysqld_exporter`@`%`, SELECT·PROCESS·REPLICATION CLIENT, 연결 상한 3 |
| 접속 파일 | `/etc/zipsai/mysql-exporter.cnf`, 0600·65534:65534, Docker DNS `mysql` 사용 |
| 기존 Exporter | 검증 후 실행 유지. 재생성·업그레이드 없음 |
| 신규 Exporter | 별도 `zipsai-monitoring` 프로젝트, `/opt/zipsai-monitoring/compose.json` |
| 기존 서비스 | ID·기동 시각·실행 상태 전후 비교. 서비스 Compose·이미지·DB 설정 변경 없음 |

Exporter 이미지는 MySQL `v0.20.0`, Node `v1.9.1`로 개발 서버의 실제 실행 버전과 맞춘다. 신규 Compose는 Exporter 두 개만 포함하며 기존 `zipsai_service-tier` 네트워크를 external로 참조한다. 새 Node Exporter는 호스트 PID·파일시스템 조회 권한이 필요한 모니터링 구성이다.

비밀번호는 서버 IAM으로 SecureString을 복호화해 메모리에서 사용한다. V1 개발은 `/zipsai/staging/mysql/exporter-password`, 운영은 `/zipsai/prod/mysql-v1/exporter-password`를 참조한다. 코드·Terraform plan/state·SSM 출력에 값은 전달하지 않는다. root 접속은 실행 중인 MySQL 컨테이너의 기존 자격 증명을 메모리로 읽어 사용하며 새 root 계정·비밀번호를 만들지 않는다.

## 2. 단계별 적용

개발·운영 활성화 변수 기본값은 false다. 실제 적용 후에는 두 값을 true로 유지해야 후속 plan에서 Association 제거가 계획되지 않는다. 변수는 비밀값이 아니며 검토한 tfvars 파일이나 명시적 인자로 고정한다.

```sh
cd terraform/legacy-v1
AWS_PROFILE=terraform terraform validate
AWS_PROFILE=terraform terraform plan \
  -var=enable_rehearsal_exporters=true \
  -var=enable_production_exporters=false \
  -out=/private/tmp/zipsai-v1-exporters-staging.tfplan
```

개발 보존 검증 후 운영 활성화를 true로 바꿔 새 plan을 만든다. 기존 인프라 변경·교체·삭제는 허용하지 않으며 SSM Document·Association의 예상 생성만 있는 저장 plan을 적용한다. 개발 재실행에서 기존 파일 inode·mtime, 서비스 컨테이너 ID·기동 시각과 Exporter ID 보존을 확인한다.

## 3. 수집·영향 확인

운영 Prometheus 대상은 `mysql-v1.prod.zipsai.internal:9100`·`:9104`, 라벨은 `environment=legacy-prod`다. 수집 대상과 Monitoring SG 전용 ingress는 기존 IaC를 유지한다. 새 포트는 EC2 사설 IP에만 바인딩한다. 개발 대상도 기존 내부 DNS를 유지한다.

SSM 결과의 `mysql_up=1`, `protected_containers_unchanged=true`, 서버별 생성 여부와 Prometheus의 두 `up=1`을 확인한다. Exporter 기동 성공만으로 운영 API·DB 이관·정합성 검증까지 완료한 것으로 보지 않는다.

## 4. 실패·복구 경계

SSM은 일괄 트랜잭션이 아니므로 중간 실패 시 새 계정·파일·이미지·컨테이너가 남을 수 있다. 출력은 안전한 오류 분류만 기록하며 실제 비밀번호를 포함할 수 있는 SQL·Docker stderr는 출력하지 않는다. 원인을 확인한 뒤 같은 설정으로 재실행한다. 기존 자격 증명 불일치는 자동 수정하지 않는다.

운영에서 이번 별도 프로젝트로 생성한 Exporter만 중지하려면 다음 범위를 사용한다. 서비스 프로젝트에는 stop/down을 실행하지 않는다. 개발에서 이미 실행하던 Exporter는 이 프로젝트 소유가 아니므로 아래 명령의 대상이 아니다.

```sh
sudo docker compose -p zipsai-monitoring \
  -f /opt/zipsai-monitoring/compose.json stop mysql-exporter node-exporter
```

Association 재실행은 중지된 기존 Exporter를 자동 재시작하지 않고 불일치로 중단한다. 명시적으로 중지한 의도를 덮어쓰지 않기 위함이다. 재개가 필요하면 해당 프로젝트의 두 Exporter만 시작하고 다시 검증한다. 모니터링 계정·접속 파일은 자동 삭제하지 않는다. Terraform의 활성화 변수를 끄면 Association 관리만 제거되며 서버에 생성된 구성은 남는다.
