# AI 팀 Parameter Store 값 관리

2026-10-21 사용자 승인으로 `Zipsai-AIParameterStoreEditors` 정책을 기존 AI 전용 그룹 `zipsai-prod-qdrant-readers`에 연결했다. 현재 구성원은 `zipsai-ai-kaia`, `zipsai-ai-linda`이며 그룹 구성원을 변경하지 않았다.

## 범위와 사용 방법

- 계정 929368845727, 서울 리전(ap-northeast-2)의 모든 파라미터. AI 경로뿐 아니라 Backend·DB·V1 공통 설정과 배포 계약·승격 기록도 포함한다.
- String·StringList·SecureString 조회, 이전 버전 조회, 실제 값 생성·수정(PutParameter)을 허용한다. 삭제·태그 변경·IAM 변경·서버 명령 실행 권한은 이 정책으로 부여하지 않는다.
- 현재 SecureString은 모두 `alias/aws/ssm`을 사용한다. 해당 키의 암호화·복호화·데이터 키 생성은 SSM 경유와 계정/리전 파라미터 암호화 컨텍스트 조건으로 허용했다. 향후 고객 관리 KMS 키 사용 시 별도 검토가 필요하다.
- AWS 콘솔은 본인 IAM 사용자로 로그인해 Systems Manager → Parameter Store → 서울 리전에서 파라미터를 선택하고 편집·저장한다.
- CLI는 기존 본인 IAM 사용자 프로필을 사용한다. `zipsai-viewer` 등 조회 전용 AssumeRole 프로필은 별도 역할이므로 이 수정 권한을 상속하지 않는다. 새 Access Key 발급이나 개인 프로필 교체는 필요 없다.
- SecureString 값을 채팅·명령행 인자·화면 캡처·Git에 남기지 않는다.

## 변경 이후

현재 기동 시 주입되는 설정은 저장만으로 실행 중 서비스에 자동 반영되지 않는다. 배포 절차로 값을 다시 읽고 컨테이너/Task를 재생성한다. V1과 V2가 공유하는 운영 설정은 두 환경의 다음 배포에 영향을 줄 수 있다. 배포 계약이나 승격 검증 기록의 수동 수정은 배포 안전장치의 신뢰성을 깨뜨릴 수 있으므로 테스트 값처럼 변경하지 않는다.

Terraform이 값을 관리하는 경로는 수동 수정 후 다음 plan에서 차이가 날 수 있다. 해당 자원의 `ignore_changes` 및 관리 주체를 확인하고 필요하면 IaC도 동기화한다. 이번 작업은 값 관리 방식을 변경하거나 파라미터 값을 수정하지 않았다.

## 적용·검증·복구

`terraform/access/ai-parameter-editors.tf`로 정책과 연결만 2 add·0 change·0 destroy 적용했다. fmt·validate 통과, 전체 후속 plan No changes를 확인했다. 두 사용자 IAM 시뮬레이션에서 비-AI 경로 조회/수정 allowed, DeleteParameter implicitDeny 및 SSM 경유 KMS Decrypt/Encrypt/GenerateDataKey allowed를 확인했다. 실제 비밀값 조회·쓰기 테스트는 하지 않았다.

증빙: `/private/tmp/zipsai-ai-parameter-access-{plan,apply,post-plan}.log`. 회수하려면 이 정책 연결을 IaC에서 제거하고 plan·apply한다. 기존 MySQL·Qdrant·Grafana 접속 권한은 별개로 유지된다.
