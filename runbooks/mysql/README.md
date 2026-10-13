# MySQL Runbooks

MySQL 계정 생성, Dump·복원, GTID 복제 연결, Primary·Replica 검증과 Rollback 절차를 관리한다.

실제 Secret 값은 문서와 Script에 기록하지 않고 실행 시 SSM Parameter Store에서 조회한다.

## Parameter Store 경로

| 환경 | 용도 | Parameter |
| --- | --- | --- |
| Staging | 애플리케이션 계정 | `/zipsai/staging/mysql/password` |
| Staging | Root 계정 | `/zipsai/staging/mysql/root-password` |
| Staging | 복제 계정 | `/zipsai/staging/mysql/replication-password` |
| Staging | Exporter 계정 | `/zipsai/staging/mysql/exporter-password` |
| Production V2 | 애플리케이션 계정 | `/zipsai/prod/mysql-v2/password` |
| Production V2 | Root 계정 | `/zipsai/prod/mysql-v2/root-password` |
| Production V2 | 복제 계정 | `/zipsai/prod/mysql-v2/replication-password` |
| Production V2 | Exporter 계정 | `/zipsai/prod/mysql-v2/exporter-password` |
| Production V1 | 임시 Exporter 계정 | `/zipsai/prod/mysql-v1/exporter-password` |

기존 V1의 `/zipsai/prod/mysql/password`와 `/zipsai/prod/mysql/root-password`는 변경하지 않는다.
