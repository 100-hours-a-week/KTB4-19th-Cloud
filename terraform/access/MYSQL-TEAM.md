# V2 MySQL — 팀원 접속 안내

현재 권장 방식은 [통합 조회 프로필 안내](DATA-VIEWER-TEAM.md)다.
아래 환경별 프로필도 기존대로 유지된다. 둘 중 한 방식만 설정하면 된다.

사전 준비: 본인 AWS CLI `zipsai` 프로필, Session Manager plugin, DBeaver.
`zipsai`는 본인의 실제 프로필 이름으로 바꾼다. 키·비밀번호를 Git/채팅에 올리지 않는다.

## 1. Role 프로필 최초 1회 설정

`YOUR_IAM_USERNAME`을 본인 IAM 사용자 이름으로 바꾼다.

```bash
aws configure set role_arn arn:aws:iam::929368845727:role/zipsai-staging-mysql-viewer --profile mysql-staging
aws configure set source_profile zipsai --profile mysql-staging
aws configure set role_session_name YOUR_IAM_USERNAME --profile mysql-staging
aws configure set region ap-northeast-2 --profile mysql-staging

aws configure set role_arn arn:aws:iam::929368845727:role/zipsai-prod-mysql-viewer --profile mysql-prod
aws configure set source_profile zipsai --profile mysql-prod
aws configure set role_session_name YOUR_IAM_USERNAME --profile mysql-prod
aws configure set region ap-northeast-2 --profile mysql-prod
```

## 2. 접속할 환경의 터널 실행

staging:

```bash
aws --profile mysql-staging --region ap-northeast-2 ssm start-session \
  --target i-0a52feda636322eb1 \
  --document-name zipsai-staging-mysql-viewer-forward \
  --parameters '{"localPortNumber":["13306"]}'
```

prod (별도 터미널):

```bash
aws --profile mysql-prod --region ap-northeast-2 ssm start-session \
  --target i-09bc1c7b767e8c45a \
  --document-name zipsai-prod-mysql-viewer-forward \
  --parameters '{"localPortNumber":["23306"]}'
```

터미널을 켜둔다. 종료는 Ctrl+C. 두 터널은 동시에 열 수 있다.

## 3. DBeaver 연결 두 개 생성

| 항목 | V2-STAGING | V2-PROD |
| --- | --- | --- |
| 드라이버 | MySQL | MySQL |
| Host | 127.0.0.1 | 127.0.0.1 |
| Port | 13306 | 23306 |
| Database | zipsai | zipsai |
| Username | zipsai_viewer | zipsai_viewer |
| Password | 별도 전달받은 staging 비밀번호 | 별도 전달받은 prod 비밀번호 |

DBeaver SSH tunnel은 켜지 않는다. SSM이 이미 터널을 제공한다.
MySQL 드라이버 설치 요청이 있으면 공식 드라이버를 설치한다.
연결 인증 오류가 있으면 비밀번호·올바른 터널·대상 환경부터 확인한다.
인증 오류를 해결하려고 무조건 TLS를 끄거나 `allowPublicKeyRetrieval=true`로 바꾸지 않는다.

테스트 연결 후 다음 SQL로 접속 서버를 확인한다.

```sql
SELECT @@hostname AS host, @@server_uuid AS server_uuid, DATABASE() AS current_schema;
SHOW GRANTS;
```

조회 계정에는 zipsai 스키마 SELECT·SHOW VIEW만 있다. INSERT/UPDATE/DELETE/DDL 권한은 없다.
운영 데이터는 조회만 하더라도 민감하므로 내려받기·공유는 팀 기준을 따른다.
환경별 조회 비밀번호는 별개이며 V1 비밀번호가 아니다.
IAM 키·Grafana 비밀번호도 DB 비밀번호가 아니다.

## 관리자 비밀번호 인계

비밀번호는 각 Primary의 `/root/zipsai-access/staging-mysql-viewer-password`,
`/root/zipsai-access/prod-mysql-viewer-password`에 root 전용으로 보관돼 있다.
관리자가 안전한 관리 세션에서 확인해 승인된 비밀 공유 수단으로 개별 전달한다.
팀원 Role에 해당 파일 조회나 SendCommand 권한을 추가하지 않는다.
이 문서와 Terraform에는 비밀번호를 넣지 않는다.
