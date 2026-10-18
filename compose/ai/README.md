# V2 AI Compose

기존 V1 운영 구성인 저장소 루트의 `compose.yaml`은 수정하지 않는다. 새 EC2 호스트별 Compose는 아래 파일을 원본으로 관리한다.

| 파일 | 대상 |
| --- | --- |
| compose-ai-api.yml.tftpl | AI API EC2 |
| compose-embedding.yml.tftpl | Embedding EC2 |
| compose-qdrant.yml.tftpl | Qdrant EC2 |

Terraform이 저장소 주소·리전·로그 그룹을 렌더링하고, 배포 시 대상 호스트의 `/opt/zipsai/compose.yaml`로 설치한다. 환경변수는 배포 시 기존 Parameter Store 값을 조회해 만든 `runtime.env`에서 주입한다. 파일은 root 소유·권한 600으로 제한하며 실제 값은 Git에 넣지 않는다.

기존 Qdrant Admin/Read-only 키를 유지한다. 기존 OpenRouter 변수명과 새 AI 전달안의 LLM_API_KEY 매핑을 구분하며, 실제 경로는 사용자 캡처를 확인한 뒤 확정한다. 이미지 호환성·기동 순서·권한·미검증 항목은 `terraform/modules/ai/README.md`를 참고한다.
