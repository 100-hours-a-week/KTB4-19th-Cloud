# Database Migration AppConfig

DB 마이그레이션 중 Container를 재배포하지 않고 Writer·읽기 비율·Outbox Worker 방향을 변경하기 위한 Runtime 설정이다.

## 설정 계약

```json
{
  "writer": "V1",
  "shadowReadPercent": 0,
  "v2ReadPercent": 0,
  "forwardWorkerEnabled": false,
  "reverseWorkerEnabled": false
}
```

| 값 | 역할 |
| --- | --- |
| `writer` | 사용자 쓰기를 Commit하는 기준 Database |
| `shadowReadPercent` | 응답에는 사용하지 않고 V2 결과를 비교할 조회 비율 |
| `v2ReadPercent` | 사용자에게 V2 조회 결과를 반환할 비율 |
| `forwardWorkerEnabled` | V1 Outbox를 V2에 반영하는 Worker 활성화 |
| `reverseWorkerEnabled` | V2 Outbox를 V1에 반영하는 Rollback용 Worker 활성화 |

두 Worker 방향을 동시에 활성화하는 설정은 JSON Schema Validator가 거부한다.

## Backend 조회 경로

ECS에서는 같은 Task의 Agent를 `localhost`로 호출한다.

```text
http://localhost:2772/applications/{application}/environments/{environment}/configurations/{profile}
```

V1 Docker Compose에서는 `http://appconfig-agent:2772`를 사용한다. Agent가 일시적으로 설정을 조회하지 못하면 Backend는 마지막 정상 설정을 유지하고, 최초 조회 실패 시에는 V1 Writer·비율 0·Worker 비활성화를 안전 기본값으로 사용해야 한다.

## V1 실행

Production AppConfig와 V2 MySQL이 준비된 후 V1 배포 환경에 `/zipsai/prod/mysql-v2/password`를 `DB_V2_PASSWORD`로 주입하고 Agent를 시작한다.

```bash
docker compose --profile migration-control up -d appconfig-agent
```

AppConfig 배포 완료 시각, Agent가 확인한 Configuration Version, 실제 Backend 적용 시각을 함께 기록한다. Agent의 Poll 간격은 5초이므로 여러 Backend가 완전히 같은 순간에 전환된다고 가정하지 않는다.
