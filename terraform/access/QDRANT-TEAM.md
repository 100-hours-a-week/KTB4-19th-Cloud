# AI팀 V2 Qdrant 조회

모든 팀원용 현재 권장 방식은 [통합 조회 프로필 안내](DATA-VIEWER-TEAM.md)다.
아래 AI 전용 환경별 프로필과 V1 권한은 기존대로 유지된다.

대상은 기존 `zipsai-prod-qdrant-readers` 그룹의 kaia/linda다.
V1 기존 접속은 유지되며 이 안내는 V2 환경별 전용 Role을 사용한다.
SSM은 통로만 제공하고 API 인증은 환경별 Qdrant 읽기 전용 키로 한다.
관리자 API 키를 공유하거나 입력하지 않는다.

## 최초 1회

`YOUR_IAM_USERNAME`은 본인 IAM 사용자 이름, `zipsai`는 본인 AWS 기본 프로필로 바꾼다.

```bash
aws configure set role_arn arn:aws:iam::929368845727:role/zipsai-staging-qdrant-reader --profile qdrant-staging
aws configure set source_profile zipsai --profile qdrant-staging
aws configure set role_session_name YOUR_IAM_USERNAME --profile qdrant-staging
aws configure set region ap-northeast-2 --profile qdrant-staging

aws configure set role_arn arn:aws:iam::929368845727:role/zipsai-prod-qdrant-reader --profile qdrant-prod
aws configure set source_profile zipsai --profile qdrant-prod
aws configure set role_session_name YOUR_IAM_USERNAME --profile qdrant-prod
aws configure set region ap-northeast-2 --profile qdrant-prod
```

## 접속할 때

staging:

```bash
aws --profile qdrant-staging --region ap-northeast-2 ssm start-session \
  --target i-03909fa361bf52be4 \
  --document-name zipsai-staging-qdrant-reader-forward \
  --parameters '{"localPortNumber":["26333"]}'
```

prod (별도 터미널):

```bash
aws --profile qdrant-prod --region ap-northeast-2 ssm start-session \
  --target i-0affe50cbc024c066 \
  --document-name zipsai-prod-qdrant-reader-forward \
  --parameters '{"localPortNumber":["36333"]}'
```

| 환경 | 대시보드 | 관리자에게 전달받을 키의 Parameter Store 경로 |
| --- | --- | --- |
| staging | http://localhost:26333/dashboard | /zipsai/staging/ai/qdrant-read-only-api-key |
| prod | http://localhost:36333/dashboard | /zipsai/prod/ai/qdrant-read-only-api-key |

터미널을 유지하고 각 주소에서 환경에 맞는 읽기 전용 API 키를 입력한다.
일반 비밀번호 관리자에 환경별로 보관할 수 있다. 브라우저 저장을 사용하는 경우 개인 PC에서만 사용하고
데이터 삭제·시크릿 창·주소/포트 변경 시 다시 입력할 수 있다. IAM 터널 Role은 Secret 조회 권한이 없다.
공유 문서·Git·단체 채팅에 키를 넣지 않는다. 종료는 Ctrl+C.

서버 포트는 6333 고정이며 사용자가 host/서버 port를 바꿀 수 없다.
각 Role은 자기 환경의 Qdrant만 허용한다. 기존 IAM 사용자 권한과 합산되지 않도록 Role을 분리했다.
조회 제한 자체는 API 키가 담당하며 IAM 그룹 이름이나 터널이 데이터 쓰기를 차단하는 것은 아니다.
읽기 전용 키로 관리 버튼이 보여도 생성·수정·삭제는 수행하지 않는다.
