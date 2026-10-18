# Production DB 이관 준비 — 통신·계정

## 관리 범위

`terraform/environments/prod/migration-preparation.tf`가 통신 규칙·Parameter 조회 권한·SSM 계정 초기화를 관리한다. 비밀번호는 운영자 소유 SecureString을 각 서버가 직접 읽는다. Terraform은 비밀번호 값을 읽거나 State에 저장하지 않는다.

기존 앱·root 비밀번호는 변경하지 않는다. GTID·복제 채널·ID 생성 규칙·업무 Schema·데이터·Backend/Agent/Worker·DNS는 이 코드의 적용 대상이 아니다.

## 계정과 권한

| 서버 | 계정 | 접속 범위 | Secret |
|---|---|---|---|
| V1 운영 | zipsai_repl | V2 Primary의 사설 IP만 | /zipsai/prod/mysql-v1/replication-password |
| V2 Primary | zipsai_app | MySQL host `%`, 네트워크는 기존 앱 SG로 제한 | /zipsai/prod/mysql-v2/password |
| V2 Primary | zipsai_repl | V2 Replica의 사설 IP만 | /zipsai/prod/mysql-v2/replication-password |
| V2 Replica | zipsai_app | MySQL host `%`, 네트워크는 기존 앱 SG로 제한 | /zipsai/prod/mysql-v2/password |

앱 계정은 `zipsai` 스키마에 SELECT·INSERT·UPDATE·DELETE·CREATE·DROP·ALTER·INDEX·REFERENCES만 가진다. 전역 권한·GRANT OPTION은 없다. 복제 계정은 REPLICATION SLAVE·REPLICATION CLIENT만 가진다.

SSM은 인스턴스 ID와 MySQL server_id를 검사한다. 계정 DDL은 세션 sql_log_bin=0에서 노드별로 실행해 향후 복제에 중복 전파하지 않는다. 기존 계정은 비밀번호를 교체하지 않고 권한을 검증하며, 예상과 다르거나 앱 인증이 실패하면 중단한다. 일부 생성 후 실패하면 계정을 자동 DROP하지 않으므로 실제 계정·GRANT를 확인하고 재개한다. read_only를 임의로 해제하지 않는다.

## 2026-10-18 적용 결과

- 신규 통신 규칙 2개·IAM 정책 2개·SSM Document 1개·Association 3개, 합계 8개 추가. 변경·삭제·교체 0.
- 첫 apply 7 added·0 changed·0 destroyed, 수신 노드의 Source Secret 조회 정책 추가 apply 1 added·0 changed·0 destroyed. 각각 저장 plan의 JSON 변경 목록을 검사했다.
- fmt·validate·단위 테스트 31개 통과. 적용 후 prod 전체 plan No changes.
- source/primary/replica Association 모두 Success. 각 실행에서 GTID·읽기 전용·자동 증가 설정 및 컨테이너/MySQL 프로세스 상태가 그대로임을 확인했다.
- 세 Association 재실행도 Success이며 모든 계정 created=false였다. 비밀번호 회전·기존 계정 재생성 없이 같은 상태를 유지했다.
- V1→V2 Primary 앱 인증과 Replica→Primary 복제 계정 인증은 SELECT·SHOW GRANTS로 통과했다. 업무 데이터 쓰기 테스트는 하지 않았다.
- V2 Primary→V1 인증은 연결 거절로 미완료. V1 Docker MySQL은 `127.0.0.1:3306`에만 게시돼 있고 사설 IP에는 Listener가 없다. SG 문제를 해결한 뒤 드러난 호스트 포트 바인딩 문제이며 비밀번호 오류로 판정하지 않는다.

아직 DB 이관 준비 전체가 끝난 것은 아니다. V1 사설 접속 경로를 별도 승인으로 해결한 뒤 Source 복제 계정의 실제 인증을 검증해야 한다. MySQL Container 재생성이나 프록시 추가는 이번 작업에서 수행하지 않았다. GTID는 여전히 OFF이며 V2에 업무 DB는 복원하지 않았다.

## 백업과 후속 작업

V1 안전용 논리 백업은 `/var/backups/zipsai/prod-pre-migration-20261018T090319Z-q7tgkqe2/zipsai.sql.gz`다. 전체 29개 테이블·gzip 무결성·Dump 완료 표시를 확인했고 SHA-256은 같은 폴더의 `manifest.json`에 보관했다. 복원 테스트는 미실행이다. 이 백업은 GTID 기준점이 없는 안전용이며 이관 Seed로 대신 사용하지 않는다.

EBS 데이터 `snap-0a1f8f29c3769c033`·루트 `snap-0f20c4a9bfebc1f7e`는 별도 생성 요청했다. 마지막 확인은 pending이므로 completed 확인이 남아 있다. 실행 중인 볼륨의 스냅샷은 MySQL 논리 일관성·복원 성공을 단독 보장하지 않는다.

다음 순서는 V1 사설 접속 해결·인증 확인 → 백업 복구 검증 → GTID/ID 정책과 마이그레이션 앱 준비 → 새로운 이관용 일관 Dump·기준점 확보 → V2 복원·GTID 추격이다. 복제 채널 중지와 Outbox 인계는 별도 단계다.

## 재적용과 복구

Cloud 원본과 M15 사본은 같은 상대 경로를 유지한다. 테스트는 `python3 -m unittest discover -s terraform/modules/mysql/scripts -p 'test_configure*.py'`로 실행한다. 이후 prod fmt·validate·전체 plan을 검토하고 저장 plan을 적용한다.

Association 제거만으로 DB 계정이 삭제되지는 않는다. 기존 Secret 변경도 자동 비밀번호 회전으로 처리하지 않는다. 중단 시 앱·GTID 상태는 유지하고, 추가 통신·IAM·SSM 자원만 새 plan으로 검토해 되돌릴 수 있다. 실제 계정 제거·권한 회수는 복제 사용 여부를 먼저 확인한 뒤 별도 승인으로 수행한다.

검증 로그와 저장 plan은 작업 호스트 `/private/tmp/zipsai-50rps-precheck.2db4HO/`에 있다. 임시 파일은 영구 증빙 저장소가 아니다.
