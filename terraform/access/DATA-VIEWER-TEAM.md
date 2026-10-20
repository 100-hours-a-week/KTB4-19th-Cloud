# 통합 V2 데이터 조회 — 팀원 안내

기존 AWS 프로필과 Access Key는 변경하지 않는다. 본인 키를 재사용하는 통합 Role 프로필 하나만 추가한다.
기존 mysql-staging/mysql-prod/qdrant-staging/qdrant-prod/Grafana 프로필도 계속 사용할 수 있다.
MySQL·Qdrant·V1의 실행 설정·계정·키는 바꾸지 않는다. 새 권한은 팀 로그 조회 그룹의 다섯 명 모두가 사용한다.

## 최초 1회 설정

`YOUR_AWS_PROFILE`은 기존 본인 IAM 사용자 프로필, `YOUR_IAM_USERNAME`은 본인 IAM 사용자 이름으로 바꾼다.
source_profile에 zipsai-viewer 자신이나 기존 assume-role 프로필을 넣지 않는다.
기존에 zipsai-viewer라는 프로필이 있다면 덮어쓰지 말고 다른 새 이름을 쓴다.

```bash
aws configure set role_arn arn:aws:iam::929368845727:role/zipsai-v2-data-viewer --profile zipsai-viewer
aws configure set source_profile YOUR_AWS_PROFILE --profile zipsai-viewer
aws configure set role_session_name YOUR_IAM_USERNAME --profile zipsai-viewer
aws configure set region ap-northeast-2 --profile zipsai-viewer

# 인증 및 Role 전환 확인. 비밀번호를 입력하는 명령이 아니다.
aws sts get-caller-identity --profile zipsai-viewer
```

## 접속할 터널 선택

필요한 명령을 별도 터미널에서 실행한 뒤 창을 유지한다. 종료는 Ctrl+C.
모두 같은 프로필을 쓰며 서버·문서·로컬 포트만 다르다.

```bash
# MySQL staging → DBeaver 127.0.0.1:13306
aws --profile zipsai-viewer --region ap-northeast-2 ssm start-session \
  --target i-0a52feda636322eb1 \
  --document-name zipsai-staging-mysql-viewer-forward \
  --parameters '{"localPortNumber":["13306"]}'

# MySQL prod → DBeaver 127.0.0.1:23306
aws --profile zipsai-viewer --region ap-northeast-2 ssm start-session \
  --target i-09bc1c7b767e8c45a \
  --document-name zipsai-prod-mysql-viewer-forward \
  --parameters '{"localPortNumber":["23306"]}'

# Qdrant staging → http://localhost:26333/dashboard
aws --profile zipsai-viewer --region ap-northeast-2 ssm start-session \
  --target i-03909fa361bf52be4 \
  --document-name zipsai-staging-qdrant-reader-forward \
  --parameters '{"localPortNumber":["26333"]}'

# Qdrant prod → http://localhost:36333/dashboard
aws --profile zipsai-viewer --region ap-northeast-2 ssm start-session \
  --target i-0affe50cbc024c066 \
  --document-name zipsai-prod-qdrant-reader-forward \
  --parameters '{"localPortNumber":["36333"]}'
```

MySQL: DB zipsai, 사용자 zipsai_viewer, 해당 환경의 조회 비밀번호를 입력한다. DBeaver SSH 터널은 끈다.
Qdrant: 해당 환경의 **읽기 전용 API 키**를 입력한다. 관리자 키를 전달하지 않는다.
키·비밀번호는 문서나 채팅에 넣지 않고 승인된 비밀 공유 수단으로 전달한다.

## 권한 경계

통합 Role은 V2 staging/prod MySQL Primary·Qdrant 네 서버와 기존 고정 포트 문서 네 개만 허용한다.
문서는 3306 또는 6333으로 서버 포트가 고정돼 있다. Role은 네 서버에서 이 두 고정 포트 문서를
사용할 수 있는 범위이며 환경·서비스별 문서와 서버의 일대일 조합을 IAM이 강제하는 구조는 아니다.
위 명령의 올바른 조합을 사용한다. 범용 포워딩·원격 host 선택·셸·SendCommand·Secret 조회는 부여하지 않는다.
Grafana·V1·Replica·AI API 서버는 이 Role의 접근 대상이 아니다.
IAM 터널은 SQL/API 읽기 전용을 보장하지 않으므로 조회 계정·읽기 전용 키를 사용해야 한다.

서버를 끄거나 정책 연결을 제거하지 않는 한 기존 접속과 서비스에 영향이 없다.
새 연결을 철회하려면 통합 Role의 그룹 연결만 제거한다. 이미 발급된 Role 세션은 만료까지
남을 수 있으므로 긴급 회수 시 별도 세션 회수가 필요하다.
