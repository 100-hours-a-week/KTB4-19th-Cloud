# V2 AI 수집 연결 — 2026-10-19

## 적용 범위

monitoring Root의 `ai-observability.tf`로 staging AI API·Embedding 지표와
AI API·Embedding·Qdrant 로그 수집을 추가했다. prod는 새 관측성 이미지 배포·검증 후 별도로 추가한다.
V1, prod 서비스, 기존 CloudWatch driver·로그 그룹·보존 기간은 변경하지 않았다.
V1 로그는 기존 CloudWatch 경로로 계속 확인하며 이 작업으로 V1 로그가 Loki에 추가된 것은 아니다.

Prometheus는 `:8000/metrics`를 15초마다 조회한다. 소스에 동적 ID를 지표 라벨로 추가하지 않는다.
SG는 모니터링 서버에서 staging 두 호스트의 8000 포트만 허용한다. 포트 전체 공개는 하지 않았다.
Qdrant metrics는 API 키 인증이 필요하므로 이번 지표 수집 대상에는 포함하지 않는다.

Alloy v1.21.0을 각 호스트의 별도 Compose project `zipsai-ai-observability`로 실행한다.
Docker discovery는 해당 호스트의 AI-owned project/service 라벨로 필터링한다.
기존 awslogs의 Docker dual-logging cache를 읽어 Loki에 병행 전송하므로 앱 재시작·로그 driver 변경은 없다.
이 캐시는 크기가 제한돼 있어 장기간 수집기 중단 시 Loki의 완전한 로그 보존은 보장하지 않는다.
CloudWatch는 검증 기간 동안 유지한다. 나중에 V2 driver를 바꾸면 다음 앱 배포와 별도 검증이 필요하며
V1 driver·그룹은 별도 정책으로 유지해야 한다.

Loki stream 라벨은 env와 service를 사용하고, trace/job/building/대화 ID는 JSON 내부에 둔다.
수집기는 로그 원문을 추가 비식별화하지 않는다. AI팀의 JSON formatter가 민감정보를 제외하는 계약이다.
Prometheus 지표의 environment와 Loki의 env는 이름이 다르므로 쿼리에서 구분한다.

## 확인 쿼리

Grafana Explore → Prometheus:

```promql
up{job="ai-application", environment="staging"}
```

```promql
zipsai_build_info{job="ai-application", environment="staging"}
```

Grafana Explore → Loki:

```logql
{env="staging", service=~"ai-api|embedding|qdrant"}
```

AI API·Embedding /health·/metrics 요청은 앱 카운터에서 제외된다.
실제 업무 요청 전 일부 counter/histogram 시계열이 아직 없는 것은 수집 실패와 구분한다.
지표 UP·로그 도착은 LLM 답변·문서 색인 업무 성공을 증명하지 않는다.

## 검증 결과 및 한계

첫 plan 13 add·2 change·0 destroy 후 새 수집기의 데이터 디렉터리 권한 문제를 발견했다.
전체 `/var/lib/alloy`를 전용 데이터 디렉터리로 마운트하도록 보완하고 실패 Association 세 개만 재생성했다.
Alloy validate, Compose YAML, Python 구문 검사와 SSM 설치/readiness가 통과했고 최종 전체 plan은 No changes다.
AI API·Embedding up=1, build version 05c7e53을 확인했다. 검증 시 최근 24시간 Loki 로그 집계는
ai-api 7·embedding 8·qdrant 506개였다. 과거 캐시 재수집을 포함할 수 있어 처리량으로 해석하지 않는다.
기존 앱 healthy·awslogs 유지와 V1 8080/8081/9100/9104 target UP, V1 AI CloudWatch 30일 보존을 확인했다.

Alloy에는 Docker socket이 연결된다. `:ro` 마운트는 Docker API 요청 권한을 읽기 전용으로 제한하지 않는다.
신뢰하는 호스트 수집기로 취급하고 UI는 127.0.0.1:12345에만 바인딩하며 cap_drop/no-new-privileges를 적용했다.
256MiB·0.5 CPU 제한은 초깃값이며 실제 부하에서 누락·재시작·전송 실패를 관찰해야 한다.
Loki는 private SG로 격리하며 VPC 내부 HTTP이고 별도 수집 인증을 추가하지 않았다.

## 복구

Prometheus 문제는 ai-application job만 제거한 설정으로 IaC apply·reload한다.
수집기 문제는 해당 호스트의 수집기 project만 중지하고, 수정된 config/Compose로 SSM 재적용한다.
앱 project·awslogs·데이터·볼륨은 변경하거나 삭제하지 않는다.
Association 삭제만으로 이미 실행 중인 수집기가 제거되는 것은 아니므로 롤백 시 별도 중지를 확인한다.
collector data 디렉터리는 읽기 위치 보존용으로 유지한다.
