# Redis EC2

환경별 Private App Subnet에 `t3a.small` 1대를 구성한다. Ubuntu 24.04 x86_64 AMI를 고정하고 공식 `redis:8.2.10` 컨테이너를 실행한다. Backend CI/CD와는 별도다.

| 항목 | 초기값 |
| --- | --- |
| CPU·메모리 | 2 vCPU·2GiB, CPU credit Standard |
| 루트 디스크 | 암호화 gp3 16GiB, 별도 Data EBS 없음 |
| Redis 메모리 기준 | `redis_maxmemory_mib=128`, `noeviction` |
| 저장 | RDB·AOF 비활성화 |
| 접속 | 기존 환경별 내부 DNS 유지, TCP 6379, TLS false |
| 인증 | 환경별 Parameter Store 사용자·SecureString 비밀번호 |
| 접근 | API·Worker SG만 허용, Public IP·SSH ingress 없음 |
| 관리 | SSM, 로그는 CloudWatch, Docker 자동 재시작 |

`maxmemory`는 프로세스 전체 RSS나 EC2 RAM의 상한이 아니다. 일부 버퍼·메모리 할당 오버헤드와 OS 공간은 추가로 필요하다. `noeviction`이므로 메모리가 부족하면 키를 자동 삭제하는 대신 메모리 증가가 필요한 명령을 거절할 수 있다. 증설은 실제 사용 메모리·키 수·명령 지연·오류를 확인한 뒤 판단한다. T3a CPU credit가 소진되면 처리 성능이 제한될 수 있다.

## 배포 경계

EC2 user data는 Docker·AWS CLI·SSM 호스트 준비만 수행한다. SSM Document·Association은 호스트에서 자격 증명을 조회해 ACL 해시 파일을 만들고 Redis를 실행한다. 비밀번호 원문은 user data, Terraform State, Document, Docker 인자·영구 환경변수에 넣지 않는다. ACL 해시 파일도 호스트 접근 권한으로 보호한다.

내부 DNS는 최초 인증 PING 검증을 수행하는 Association 뒤에 생성한다. 설정이 같으면 Association 재실행 시 Redis를 재시작하지 않는다. 이미지·설정·인증 변경은 단일 컨테이너를 교체하므로 짧은 중단과 임시 상태 초기화가 발생한다. 실패 시 자동으로 이전 설정을 복구하는 배포 기능은 없으며, 이전 코드·SSM 자격 증명과의 호환성을 확인하고 이전 설정을 재적용해야 한다. Secret 값 변경만으로 서버가 자동 재시작하지는 않는다. 비밀번호 회전 때는 version과 API·Worker 재배포 순서를 함께 관리한다.

## 적용 전 확인

Staging·Production Root에서 Valkey 모듈 호출·보존 플래그·입력·Output을 제거했다. 2026-10-16 사용자에게 사용 서비스가 없음을 확인받고 승인된 Valkey 전용 삭제 plan만 적용했다. Cache·사용자·그룹·전용 SG/규칙·기존 비밀번호 Parameter 7개를 삭제했고 AWS 캐시 목록 및 Terraform State에서 제거를 확인했다. Redis·AI 생성은 적용하지 않았다. 이전 Valkey 모듈 소스는 이력 참고용으로만 남아 있으며 어느 환경에서도 호출하지 않는다.

1. plan에서 Valkey 삭제 대상과 기존 EC2·SG 연결·SSM 권한 보존을 확인한다.
2. 기존 Valkey 삭제는 별도 완료됐으므로 Redis 준비 전 Valkey로 자동 복귀하지 않는다. 클라이언트 전환은 새 Redis 인증·DNS·Pub/Sub 검증 이후 진행한다.
3. 운영자가 `/zipsai/<env>/redis/password`를 SecureString으로 직접 생성한다(16~128자, 줄바꿈 없음, 기본 AWS 관리형 SSM 암호화 키 기준). Terraform은 이 Parameter의 값 조회·생성·수정·삭제를 하지 않으며 경로와 ARN만 참조한다. 비밀번호를 Terraform 변수·채팅·코드에 입력하지 않는다. 사용자명 String Parameter는 Terraform이 생성한다.
4. 승인 후 적용하고 Redis의 SSM 접속·인증·DNS·Pub/Sub·재시작 복구를 검증한다. Redis SSM Association은 apply 중 실행되므로 비밀번호 Parameter가 없으면 Redis 설정 단계가 실패한다. AI의 지연 배포와 달리 Redis 비밀번호는 Redis apply 전에 준비한다.
5. API·Worker 연결과 동작을 확인한다. 최종 API 목표 2 Tasks와 현재 desired count 0은 구분하며 이 모듈에서 올리지 않는다. 비밀번호를 변경한 뒤에는 `redis_password_version`을 증가시켜 Redis 설정을 재배포하고 클라이언트도 재배포한다. 이 입력은 SSM Parameter 자체의 버전을 관리하지 않는다.

Valkey Cache 삭제로 임시 상태와 기존 Valkey 비밀번호 Parameter가 제거됐다. 이전 구성을 다시 만들더라도 삭제한 캐시 임시 상태는 복구되지 않는다. Terraform State 버킷의 버전 관리는 켜져 있지만 State 복구가 삭제된 캐시 데이터 복구를 뜻하지 않는다.

기존 Fargate Redis 구성은 AWS에 적용하지 않았으므로 ECS/Cloud Map 자원의 실제 삭제·State 이동은 수행하지 않는다. 실제 배포 이력이 달라졌다면 먼저 State를 재확인한다. V1·Staging 기존 SG·스케줄러를 수정하지 않는다.

## 한계

단일 호스트로 자동 Failover가 없고, 호스트·컨테이너 재시작 중 Pub/Sub 이벤트 전달이 중단될 수 있다. 업무 원본은 MySQL에 두며 재조회 동작을 별도로 검증한다. 디스크는 호스트·이미지·로그용이며 Redis 데이터 내구성을 제공하지 않는다. EC2·AMI 교체는 삭제 방어로 차단하고 별도 교체 계획을 요구한다. AWS apply, SSM Association 실행, 실제 컨테이너 기동·복구는 코드 문법 검사나 plan만으로 검증되지 않는다.
