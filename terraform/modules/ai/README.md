# 환경별 AI EC2

AI팀 전달안과 Cloud 레포의 기존 `compose.yaml`을 기준으로 새 V2 호스트를 분리한다. 기존 V1 Compose·컨테이너·SG·스케줄러는 수정하지 않는다. Terraform은 AWS 호스트와 배포 계약을 준비하며, AI 이미지 빌드·애플리케이션 배포는 별도다.

## 초기 구성

| 서비스 | 환경별 수량·사양 | 디스크 |
| --- | --- | --- |
| AI API | 1대, t3a.large, 2 vCPU·8GiB | 루트 gp3 40GiB |
| Embedding | 1대, t3a.large, 2 vCPU·8GiB | 루트 gp3 30GiB |
| Qdrant | 1대, t3a.small, 2 vCPU·2GiB | 루트 gp3 16GiB + 별도 데이터 30GiB |

staging/prod 각각 3대이며 Ubuntu 24.04 x86_64 AMI를 고정한다. Qdrant 2GiB는 AI팀의 시작 제안 4GB에서 사용자 결정으로 축소한 값이다. OOM·실제 메모리·포인트 수·검색 지연 검증 전 충분하다고 확정하지 않는다. CPU credit는 Standard이며 지속 부하에서 제한될 수 있다.

세 호스트는 기존 Private App Subnet 2c에 배치하고 Public IP·SSH ingress를 만들지 않는다. API/Worker SG만 AI API:8000에 접근하며, AI API SG만 Embedding:8000과 Qdrant:6333에 접근한다. NAT는 이미지·패키지 다운로드, AWS API와 외부 HTTPS 경로로 사용한다. 내부 HTTP는 암호화되지 않으므로 SG 격리가 전송 암호화를 대신하지는 않는다.

Qdrant 데이터 EBS는 암호화·삭제 방어·분리 Attachment로 보존한다. 마운트 실패 시 루트 디스크에 데이터를 쓰지 않도록 Compose bind의 `create_host_path:false`와 배포 전 mountpoint 확인을 사용한다. 백업 주기·보존, Snapshot/복구와 기존 데이터 이관은 아직 구현·검증하지 않았다. 삭제 방어가 백업을 대신하지 않는다.

## Compose와 환경변수

실제 Compose 관리 위치는 Cloud 레포의 `compose/ai/compose-{ai-api,embedding,qdrant}.yml.tftpl`이다. Terraform이 이미지 저장소·로그 그룹·리전을 렌더링한다. 배포 시 호스트 `/opt/zipsai/compose.yaml`로 전달하며 기존 V1 파일은 그대로 둔다.

| 구분 | 관리 방식 |
| --- | --- |
| 이미지 SHA | AI API·Embedding은 명시적인 SHA7 선택. Qdrant는 v1.19.1 고정 |
| 일반 설정 | 환경·서비스별 String JSON `/zipsai/<env>/ai/<service>/runtime`. 초기값 이후 Console/CD 값 유지 |
| 기존 일반 Parameter | `ai_api_runtime_parameter_names`·`embedding_runtime_parameter_names`에 변수명→기존 경로를 매핑. 초기 JSON보다 우선 적용 |
| 비밀값 | 기존 SecureString 경로만 매핑. Terraform은 값 조회·생성·수정·복사를 하지 않음 |
| 호스트 주입 | 배포 때 SSM 조회 → root 소유 runtime.env, 권한 600 → Compose 주입 |

사용자 확인에 따라 staging/prod는 각각 `/zipsai/<env>/ai/` 아래를 참조한다. `langfuse/base-url`, `langfuse/public-key`, `llm-model`은 String, `langfuse/secret-key`, `qdrant-admin-api-key`, `qdrant-read-only-api-key`는 SecureString으로 연결한다. Langfuse public key를 비밀값 맵에 넣지 않는다. 환경별 경로만 연결하며 prod 값을 staging으로 자동 복사하거나 공유 경로로 우회하지 않는다.

이 경로들의 값은 Terraform이 조회·생성하지 않고 실제 SSM 배포 때 읽는다. 따라서 미생성 Parameter가 있어도 AI 기반 인프라 생성은 가능하며, 실제 서비스 배포 전에 값을 추가해야 한다. Langfuse를 선택 사항으로 바꾸거나 누락 오류를 무시하지 않는다. RunPod 주소·모델·키는 미확정 상태를 유지하며 임시 값이나 기존 OpenRouter 키로 채우지 않는다. `LLM_API_KEY`의 기본 참조 이름은 `llm-api-key`이며 실제 키는 배포 전 준비한다. Compose의 `OPENROUTER_API_KEY`는 같은 키의 호환 이름일 뿐 코드 호환성을 보장하지 않는다. 실제 값은 채팅·저장소·Terraform 변수 파일로 받지 않는다.

호스트 분리에 필요한 `QDRANT_URL`·`EMBEDDING_API_URL`·S3 Bucket·리전은 새 환경의 인프라 값으로 초기화한다. 일반 Parameter 매핑에 예전 Docker 서비스명 주소를 넣지 않는다. `LLM_BASE_URL`·`LLM_MODEL`·`VLM_MODEL`은 기존 값과 실제 RunPod 모델 계약을 확인해 채운다. 초기 빈 값으로 AI API를 배포하면 사전 검사에서 중단한다.

새 AI Role만 Parameter 읽기를 지정 경로로 제한한다. AmazonSSMManagedInstanceCore의 GetParameter(s) 전체 허용을 별도의 명시적 Deny/NotResource로 제한하며 기존 V1/Redis/DB IAM은 수정하지 않는다. 사용자 관리형 KMS Key를 쓰면 `ai_parameter_kms_key_arns`도 지정한다. root/Docker 관리 권한 보유자는 런타임 Secret에 접근할 수 있다.

Production은 기존 운영 로그 그룹(`/zipsai/prod/ai-api`, `embedding`, `qdrant`)을 인수·수정하지 않고 `log_group_prefix=/zipsai/prod/ai`로 V2 로그를 분리한다. Staging 기존 경로는 유지한다. 2026-10-16 prod 생성 시 기존 그룹 이름 충돌을 확인해 추가한 경계이며, 기존 로그·30일 보존 설정은 변경하지 않았다.

## 배포와 검증

Terraform apply만으로 애플리케이션을 시작하지 않는다. 호스트에는 도구·디스크를 준비하고, 서비스별 SSM 배포 Document와 `/zipsai/<env>/ai/deployment-contract`를 만든다. SSM Document 실행 시 최신 Compose·스크립트·경로 매핑을 설치한 뒤 명시적으로 배포한다. 이미지/일반 설정 변경을 EC2 교체로 처리하지 않는다.

기동 순서는 Qdrant → Embedding → RunPod 준비 확인 → AI API → Backend/Worker 연결이다. SSM Document를 각각 호출하는 배포 Pipeline/운영자가 순서를 지킨다. 새 Backend 계약의 기본 AI 주소는 `http://ai-api.<env>.zipsai.internal:8000`이며 현재 API·Worker Task 수 0은 바꾸지 않는다.

배포 helper는 ECR 로그인·pull·Compose 교체·최대 15분 health 대기를 수행하고 실패 시 이전 env의 재적용을 시도한다. 이전 설정의 health까지 복구됐다고 보장하지 않는다. 성공한 로컬 SHA를 기록하며 동일 저장소에서 현재·직전 SHA7 이미지만 남기도록 정리한다. CI/CD의 SSM current-sha 갱신·운영 승격 정책은 실제 AI 저장소 Workflow를 확인한 뒤 연결해야 한다. 기존 자동 배포를 수정하거나 실행하지 않았다.

단일 컨테이너 교체는 무중단 배포가 아니다. AI health는 실제 Qwen 생성·이미지 처리·문서 색인 성공을 증명하지 않으므로 별도 end-to-end 테스트를 수행한다. RunPod GPU 종류·revision·모델·endpoint·키는 이 AWS 모듈에서 만들지 않는다.

## 전달안과 기존 Compose의 차이

- 기존 AI 변수는 OpenRouter 이름이고 전달안은 OpenAI 호환 `LLM_API_KEY`다. 선택한 이미지가 새 계약을 지원하는지 AI팀 코드로 확인해야 한다.
- 기존 Embedding은 Qdrant 접속값·Admin Key를 받지만 전달안의 Embedding은 임베딩 추론만 담당한다. 새 SG는 전달안대로 AI API→Qdrant만 허용한다. 기존 Embedding 이미지를 검증 없이 재사용하지 않는다.
- Worker의 색인 202는 접수이지 완료가 아니다. 완료 조회·재시도·멱등성·SQS 메시지 삭제 계약은 Backend/AI팀 확인 전 완료로 표시하지 않는다.
- Qdrant 2GiB·단일 호스트·동일 AZ, 실제 이미지 기동, EBS 복구, 모델 호출과 배포 Rollback은 아직 실행 검증 전이다.

## AI-owned V2 배포의 정기 이미지 정리 — 2026-10-19

**후속 변경:** 사용자 요청으로 아래 30분 Association은 같은 날 제거했다. 수동 감사/복구용 SSM 문서는 유지한다.
현재 정책은 AI CD 전달본의 성공 후 직전 이미지 한 개 정리이며, 자동 배포 원격 반영은 AI팀 적용이 필요하다.
아래 내용은 최초 정기 정리 적용 당시 기록이다.

현재 AI 레포 CD는 `/opt/zipsai/ai-v2/current`와 서비스별 Compose project를 사용한다.
위 기존 Cloud deploy.sh의 이미지 보존 규칙과 별개로 `image-cleanup.tf`가 관리하는 SSM 문서·Association을 추가했다.
staging/prod의 AI API·Embedding 네 서버에서 UTC 매시 0/30분에 정리한다. 최초 apply 시 즉시 실행하지 않는다.
정책 변경은 Terraform apply로 반영하며 서비스 배포·재시작은 수행하지 않는다.

스크립트는 CD와 같은 deploy.lock을 사용한다. 배포 중·현재 정상 release 없음·서비스 비정상은 건너뛴다.
모든 컨테이너(중지된 것 포함)의 참조 이미지와 현재 정상 release의 IMAGE_URI를 보호한다.
정해진 서비스 ECR 저장소에만 속하는 미사용 이미지만 `docker image rm`으로 지운다.
다른 저장소와 공유된 이미지, 소속을 알 수 없는 dangling 이미지, 볼륨·컨테이너·빌드 캐시는 삭제하지 않는다.
강제 삭제 및 전역 docker prune은 사용하지 않으며 runtime.env 값은 출력하지 않는다.

일반 실행은 30분 주기이므로 CD 성공 직후 정리 또는 짧은 간격의 연속 배포 공간을 보장하지 않는다.
필요 시 운영자가 전용 SSM 문서를 먼저 Mode=audit로 확인하고 Mode=apply로 실행한다.
문서 이름은 `zipsai-<환경>-<ai-api 또는 embedding>-image-cleanup`이다.
이전 release의 로컬 이미지는 정리될 수 있다. 같은 digest의 과거 버전 재배포는 ECR에서 다시 pull해야 한다.
ECR 보존 정책으로 이미지를 삭제하면 이 복구도 불가능하므로 ECR 수명주기는 별도 검토한다.
소스 이미지 자체가 디스크보다 크거나 추출 임시 공간이 부족하면 이미지 축소 또는 EBS 확장이 필요하다.

staging/prod 각각 전체 plan·apply 4 add·0 change·0 destroy를 확인했다.
staging Embedding에서 audit 후 미사용 a371f4fb3c6c 이미지 한 개를 삭제했고,
여유 공간 약 7.8GiB→17GiB, 사용률 73%→42%, 기존 컨테이너 healthy·/health 200을 확인했다.
삭제한 이미지는 ECR에서 재다운로드할 수 있다. AI CD 코드는 수정하지 않았고 실패 배포 재실행도 하지 않았다.
