# 2026-10-19 V1 prod → V2 prod Qdrant 이관 기록

사용자가 staging 제외·V1 원본 보존을 지정하고 실제 스냅샷 이관을 승인했다.
검증 시점의 데이터를 복원한 결과이며 이후 V1 변경분의 지속 동기화나 운영 DNS 전환은 아니다.

## 대상과 사전 확인

| 구분 | 원본 | 대상 |
| --- | --- | --- |
| EC2 | i-06c0ca0d997f03792 | i-0affe50cbc024c066 |
| 사설 주소 | 10.0.1.239 | 10.0.10.82 |
| Qdrant | 1.19.1 | 1.19.1 |
| 데이터 경로 | /data/qdrant | /data/qdrant |
| 컬렉션 | documents·195 points·green | 컬렉션 0개 |

원본은 Dense named vector `dense` 1024차원·Cosine, Sparse named vector `sparse`, shard/replication 각 1이다.
payload index는 building_id(keyword·tenant), doc_id(keyword)다. Alias는 양쪽 모두 없었다.
V1 Embedding aa18cc0과 V2 검증 이미지 소스의 기본 모델은 모두 BAAI/bge-m3이며 실행 환경의 모델 override는 없었다.
staging에는 명령을 보내지 않았다. API Key와 문서·벡터 원문은 출력하지 않았다.

## 실제 수행

1. V1 전체 points scroll로 ID·payload·Dense/Sparse vector의 canonical SHA-256을 계산했다.
2. V1 documents collection snapshot을 생성하고 root 전용 backup 폴더로 다운로드했다.
3. 스냅샷 전후 전체 points·설정 해시가 같은 것을 확인했다.
4. 양 서버 localhost 임시 전송기와 SSM 포트포워딩으로 로컬 메모리를 경유해 전달했다.
   단기 token·파일명 allowlist·최대 64MiB·240초 자동 종료를 적용했고 공개 포트·S3 업로드는 사용하지 않았다.
5. 전송 양단 SHA-256 검증 후 V2가 여전히 빈 대상임을 다시 확인했다.
6. Qdrant snapshot upload에 `wait=true`, `priority=snapshot`, checksum을 지정해 documents를 복원했다.
   기존 컬렉션이 하나라도 있으면 덮어쓰지 않고 중단하도록 했다.
7. V2 green·195 points, 전체 데이터·설정 해시를 확인했다. 전송기 두 명령은 Success로 종료됐고 임시 터널도 종료했다.

일반 채팅은 중단하지 않았으며 문서 등록·수정·삭제는 작업 중 하지 않도록 사용자에게 안내했다.
작성 경로를 강제 잠그거나 원본 서비스를 중지하지는 않았다. 스냅샷 전후 및 복원 검증 시점의 원본 해시가 같았다.

## 보관 위치와 무결성

- 원본 폴더: `/var/backups/zipsai/qdrant-prod-seed-20261019-1q25zgvr`
- 원본 Qdrant snapshot: `documents-2123624752375870-2026-10-19-06-33-51.snapshot`
- 대상 폴더: `/var/backups/zipsai/received-qdrant-prod-20261019-5vnig7r5`
- 각 폴더에 `documents.snapshot`·`manifest.json` 보관. 대상에는 `restore-report.json`도 보관.
- snapshot: 3,535,360 bytes
- snapshot SHA-256: `b6a1c8fca8d1ccdb316ea22beac36616f6858b1d78f7b694193aa9d92069319d`
- 195개 points(ID·payload·모든 vectors) SHA-256: `6815a4e5f7a79fc32b3f57b79df476921245b48dba37b375294194a2d46d451d`
- vectors·sparse·shard/replica·payload index 설정 SHA-256: `50dd8be7faee16a41c4f34b9b7e325d0f0d36edabdeac86e514590513b14653a`

## 검색·앱 연결 검증

정렬된 points의 처음/중간/마지막 3개 vector로 각각 Dense/Sparse exact top-5 검색을 비교했다.
6개 중 5개는 ID·점수까지 일치했다. 마지막 Dense 표본은 5위 점수가 0.46725655인 포인트가 3개이고
그보다 높은 점수가 4개라, top-5 경계에서 선택되는 ID만 달랐다. 해당 query를 195개 전체로 확대해
ID별 점수를 정렬한 결과 SHA-256이 양쪽 모두 `1a056736e815aa79dfacef91021e73394073cc62bf143ada4d882920a0fa166c`로 일치했다.
데이터 누락이나 점수 변경으로 해석하지 않는다.

실제 prod AI 컨테이너의 QDRANT_URL·API Key로 documents GET에 성공했고 195 points·green을 확인했다.
AI 컨테이너 healthy·로컬 `/health` 200도 확인했다. 사용자 채팅 전체·LLM 최종 답변·신규 문서 색인은
자동 실행하지 않았으므로 이 검증으로 완료 처리하지 않는다.

## 영향·복구 경계

V1 원본 collection·서비스·AI 접속 설정은 보존했고, staging·MySQL·DNS는 변경하지 않았다.
V2 기존 collection은 없었으므로 복원으로 documents 하나만 추가됐다. 스냅샷은 양쪽에 보존했다.
지속 복제는 구성하지 않았다. 이후 V1 문서 변경은 V2에 자동 반영되지 않는다.
복구 시 V1을 계속 사용하거나 보관 snapshot을 이용할 수 있으나, 이후 V2 신규 쓰기가 발생한 상태에서
무작정 collection 삭제·snapshot 재복원을 하면 해당 변경을 잃을 수 있으므로 별도 승인이 필요하다.

## 실행 증빙

| 작업 | SSM Command ID |
| --- | --- |
| 원본 snapshot·전후 안정성 | 067b5adc-870a-4c2f-b6f8-d4e9abf5e7fc |
| 대상 사전 점검 | 44b537c9-0032-48e2-a311-b0aa055307d1 |
| source 전송기 | 63e79c62-75a5-4d90-8997-48f6bb740b20 |
| target 전송기 | a34d040f-46d2-4b61-a9eb-4749d3d5c511 |
| target 복원·전체 해시 | 6e217fb4-ba84-4bf1-8d2f-571d3aedb6a2 |
| 원본 재검증 | 39dfa5a1-7380-4149-9883-57e4dfebe95b |
| source 검색 상세 | 55b2915f-3791-4d84-83b5-3c73fbbbbe54 |
| target 검색 상세 | 39624509-827c-40a2-907c-70a8fbf3be75 |
| source Dense 동점 전체 비교 | fcdcfa76-62b9-48d6-a924-68a0694ed11f |
| target Dense 동점 전체 비교 | 5f518c3b-6007-4bed-92f3-5ad56d5661e5 |
| 실제 AI→Qdrant 인증 조회 | da3fa743-5f8b-480c-8548-e5a28bc1ccdb |

실행용 helper는 `/private/tmp/zipsai-50rps-precheck.2db4HO/`의 qdrant 관련 Python이다.
이 기록의 경로·checksum은 해당 1회 이관용이며 재실행 입력값으로 무조건 재사용하지 않는다.

참고: [Qdrant snapshot 이관](https://qdrant.tech/documentation/operations/snapshots/),
[upload 복원·checksum](https://api.qdrant.tech/api-reference/snapshots/recover-from-uploaded-snapshot).
