# 팀 로그 조회·Grafana 접속 권한

## 통합 MySQL·Qdrant 조회 프로필 — 2026-10-19

`data-viewer.tf`는 기존 권한을 합산하지 않는 `zipsai-v2-data-viewer` Role을 추가한다.
기존 로그 조회 그룹의 다섯 명 모두 staging/prod MySQL Primary·Qdrant를 조회할 수 있다.
기존 V1 정책·환경별 Role·Grafana Role·사용자·그룹 구성원·Access Key는 유지한다.
새 키 없이 원래 IAM 사용자 프로필을 source로 `zipsai-viewer` 하나를 최초 설정한다.
접속 명령과 인증값 구분은 [통합 팀원 안내](DATA-VIEWER-TEAM.md)를 사용한다.
별도로 환경별 MySQL 조회 비밀번호·Qdrant 읽기 전용 키가 필요하다.
fmt·validate·전체 plan 4 add·0 change·0 destroy 검토 후 apply 4 added로 완료했다.
후속 전체 plan No changes와 IAM 시뮬레이터 21개 검사 통과를 확인했다.
팀원 5명 AssumeRole, 네 조회 대상, 범용 터널·셸·V1·Grafana·Replica·AI API·SendCommand·Secret 거부,
자기 세션 종료 허용·타인 세션 종료 거부를 검사했다. 팀원 자격의 실제 터널·DB/API 로그인은 별도 필요하다.
증빙은 `/private/tmp/zipsai-unified-data-viewer-{plan,post-plan}.log`다.

## V2 MySQL 조회 접속 추가 — 2026-10-19

`mysql-viewers.tf`는 staging/prod Primary에 대한 전용 Role·정책·Session 문서를 정의한다.
현재 코드는 fmt·validate 통과, 전체 plan 8 add·0 change·0 destroy로 검증한 뒤 사용자 승인으로 apply했다.
적용 결과 8 added·0 changed·0 destroyed, 후속 전체 plan No changes를 확인했다.
기존 로그 조회 그룹 5명에게 두 Role의 AssumeRole만 추가하는 구성이다.
기존 V1 DB 그룹·계정·권한과 Grafana 권한은 변경하지 않는다.

| 환경 | CLI Role 프로필 | Role 이름 | DBeaver Host/Port |
| --- | --- | --- | --- |
| staging | mysql-staging | zipsai-staging-mysql-viewer | 127.0.0.1:13306 |
| prod | mysql-prod | zipsai-prod-mysql-viewer | 127.0.0.1:23306 |

환경별 Role은 자기 Primary와 전용 Session 문서만 허용한다. 서버 포트는 3306 고정이며
다른 환경·Grafana·셸·SendCommand 권한은 포함하지 않는다. MySQL 비밀번호/계정 생성은 포함하지 않는다.
IAM 터널 권한은 SQL의 읽기 전용을 보장하지 않는다. 별도로 `zipsai.*`의 SELECT·SHOW VIEW만
부여한 계정이 필요하며 앱/root 계정을 공유하지 않는다. 비밀번호는 Terraform state에 저장하지 않는다.

2026-10-19 두 Primary에 `zipsai_viewer`@`127.0.0.1`을 생성했다. 환경별 별도 랜덤 비밀번호는
각 서버 `/root/zipsai-access/<환경>-mysql-viewer-password`에 root 전용 0600으로 보관했다.
TCP 로그인·테이블 목록 29개·SHOW GRANTS로 SELECT/SHOW VIEW만 부여됐음을 확인했다.
사용자 연결 수 제한은 10이다. 생성 세션의 sql_log_bin만 꺼 계정 DDL을 복제하지 않았다.
비밀번호 전달 및 팀원 DBeaver 접속 검증은 아직 수행하지 않았다.

apply 후 본인 AWS source 프로필을 사용해 아래 형식으로 환경별 Role 프로필을 설정한다.

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

Source 프로필 `zipsai`는 각자 사용하는 실제 AWS 프로필로 바꾼다.
서버 ID와 문서 이름은 `terraform output mysql_viewer_connections`의 환경별 값을 사용한다.
DBeaver 연결은 `V2-STAGING`/`V2-PROD`로 각각 만들고 DB는 `zipsai`로 지정한다.
서버 식별은 `SELECT @@hostname, @@server_uuid, DATABASE();`로 확인한다.
스키마 이름이 같아도 별도 서버이며 연결/포트를 혼용하지 않는다.

이 Root는 기존 로그 조회 권한을 보존하면서 Grafana 접속을 분리한다.
State는 `access/terraform.tfstate`이며 monitoring Root의 출력으로 서버 ID를 참조한다.

## 관리 범위

- import: `zipsai-prod-log-viewers`, `Zipsai-ReadProductionLogs`, 두 리소스의 연결.
- 추가: Grafana 전용 Session 문서, IAM Role 및 Role 정책, 그룹의 AssumeRole 정책·연결.
- 제외: IAM 사용자 생성·삭제·그룹 구성원 변경, Grafana 사용자·비밀번호, 다른 그룹, 로그 수집 방식.
- import 당시 구성원: zipsai-fullstack-luna/mark/russell, zipsai-ai-kaia/linda. 구성원은 기존 IAM 가입 상태를 사용한다.

기존 CloudWatch 정책은 그대로 유지했다. `prevent_destroy`로 기존 그룹·정책의 삭제를 보호한다.
State와 plan 파일은 Git에 넣지 않는다. `.terraform.lock.hcl`은 코드와 함께 보관한다.

## 왜 전용 Role인가?

기존 DB viewer 정책은 범용 포트포워딩 문서를 허용한다. IAM 사용자의 정책에 모니터링 서버
StartSession 권한을 바로 추가하면 이 권한들이 합산되어 다른 포트 접근까지 가능해진다.
따라서 그룹에는 `sts:AssumeRole`만 추가하고 실제 세션 권한은 `zipsai-grafana-viewer` Role에 둔다.
Role을 사용하면 원래 사용자의 DB 정책이 세션 권한에 합쳐지지 않는다.

Role은 모니터링 서버와 `zipsai-grafana-port-forward` 문서만 허용한다.
문서는 서버 포트 3000을 고정하며 host/portNumber 입력을 받지 않는다.
일반 셸, SendCommand, 다른 서버, 범용 포워딩 문서는 이 Role에서 허용하지 않는다.
기존 사용자의 DB 접속 권한을 제거하는 정책은 아니다.

## 팀원 최초 설정

AWS CLI와 Session Manager plugin이 필요하다. 기존 본인 CLI 프로필을 사용하고 Access Key를 공유하지 않는다.
AWS 콘솔 비밀번호와 Grafana 비밀번호는 이 명령에 입력하지 않는다.

아래 `YOUR_AWS_PROFILE`과 `YOUR_IAM_USERNAME`을 본인 값으로 바꾼다.
IAM 사용자 이름 예: `zipsai-fullstack-luna`. Role session name은 IAM 사용자 이름과 같아야 한다.

```bash
aws configure set role_arn arn:aws:iam::929368845727:role/zipsai-grafana-viewer --profile grafana
aws configure set source_profile YOUR_AWS_PROFILE --profile grafana
aws configure set role_session_name YOUR_IAM_USERNAME --profile grafana
aws configure set region ap-northeast-2 --profile grafana
```

이후 이 Root의 `grafana_port_forward_command` 출력 명령을 실행한다. 현재 대상은 다음과 같다.

```bash
aws --profile grafana --region ap-northeast-2 ssm start-session \
  --target i-0cb4ce9d37eaf9ef5 \
  --document-name zipsai-grafana-port-forward \
  --parameters '{"localPortNumber":["3000"]}'
```

창을 유지한 채 `http://localhost:3000`에 접속하고 별도의 Grafana Viewer 계정으로 로그인한다.
종료는 Ctrl+C. 로컬 3000이 사용 중이면 localPortNumber만 13000 등으로 바꾸고 해당 주소로 접속한다.
서버 포트는 바뀌지 않는다. 사용자의 base 프로필로 범용 포워딩 명령을 실행하는 방식은 아니다.

## 검증·복구 경계

2026-10-19 기존 3개 리소스는 0 add/change/destroy로 import했다.
추가 권한 적용 중 기존 DB 정책과의 합산을 발견해 직접 StartSession 부여를 제거하고 Role로 격리했다.
기존 CloudWatch 정책 버전 v3·정책 연결과 그룹 구성원 5명은 유지했다.
Session 문서의 실제 터널·Grafana health는 관리자 자격으로 확인했다.
팀원 5명의 Role 전환 허용·모니터링 직접 포워딩 거부·기존 로그 권한 유지,
Role의 전용 문서 허용·범용 포워딩/셸/V1/SendCommand 거부·자기 세션 종료 제한을
IAM 시뮬레이터 22개 검사로 확인했다. 후속 전체 plan은 No changes였다.
팀원 전용 Role 자격의 실제 접속과 Grafana Viewer 로그인은 별도 검증 대상이다.

접속 권한 회수는 추가한 그룹의 Grafana 정책 연결을 먼저 제거한다.
기존 CloudWatch 그룹·정책을 삭제하거나 다른 Root에 중복 import하지 않는다.
AI 로그 수집 변경·Grafana 계정 발급은 이 Root 적용에 포함되지 않는다.

참고: [세션 문서 권한 검사](https://docs.aws.amazon.com/service-authorization/latest/reference/list_ssm.html),
[자기 세션 종료 제한](https://docs.aws.amazon.com/systems-manager/latest/userguide/getting-started-restrict-access-examples.html#restrict-access-example-user-sessions).
