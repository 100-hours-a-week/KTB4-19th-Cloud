# Staging 매일 01:00 KST 자동 종료

2026-10-29 검증을 위해 08:40으로 일시 변경했고, 실제 종료 성공 확인 후 매일 **01:00 Asia/Seoul**로 복원했다. 해당 실행 `0ec6204b-ca71-4ad7-a89f-61defaca8a70`은 08:40:11 시작, 08:43:35 Success였다. API 태스크는 08:42:52 STOPPED, staging EC2 5대 모두 stopped와 API/worker desired/running/pending=0을 확인했다. 정상 종료는 태스크 drain·OS 종료를 기다리므로 예약 시각과 완료 시각이 다르다. 복원 시 스케줄 target plan에도 ECS 서비스 의존성이 포함되어 API/worker desired가 1로 재설정되는 실수가 있었다. 즉시 두 서비스를 desired=0으로 복원했으며 EC2는 시작하지 않았다. 향후에는 target만으로 안전하다고 판단하지 말고 plan에 의존성 변경이 포함되는지 검증을 실패 즉시 중단 방식으로 실행하고, 종료 상태 유지용 입력을 사용해 ECS 변경을 제거한 뒤 apply해야 한다.

## 범위

EventBridge Scheduler `zipsai-staging-nightly-shutdown`(group `zipsai-staging-power`)가 매일 01:00 Asia/Seoul에 SSM Automation `zipsai-staging-nightly-shutdown`을 호출한다. 로컬 컴퓨터나 GitHub runner가 켜져 있을 필요가 없다. 자동 시작 스케줄은 만들지 않는다.

종료 대상은 staging ECS API·worker 두 서비스와 MySQL Primary·Redis·AI API·Embedding·Qdrant EC2 다섯 대다. prod, 공용 monitoring/NAT, ALB, CloudFront, S3, EBS는 정지·삭제하지 않는다. EC2 컴퓨팅/Fargate 실행 비용 절감이며 EBS·ALB·NAT 등 남는 비용은 계속 발생한다. Scheduler/SSM Automation 사용량은 서비스별 과금·무료 사용량 범위에 따라 달라지므로 전체 구성을 무조건 무료라고 표현하지 않는다.

## 종료 순서와 안전장치

1. 코드에 포함된 현재 인스턴스 ID·Project/Environment/Name 태그와 staging 서비스명을 확인한다.
2. staging API·worker desired_count를 0으로 설정한다.
3. 실행 중이던 태스크가 STOPPED가 되고 서비스 running/pending이 0이 될 때까지 최대 약 5분 기다린다. 도중 수동 시작·배포로 desired_count가 바뀌면 EC2 중지를 중단한다.
4. EC2 다섯 대를 일반 StopInstances로 중지하고 stopped 상태를 기다린다. 강제 종료·terminate·볼륨 삭제는 하지 않는다.

따라서 01:00은 종료 절차 시작 시각이다. Scheduler는 분 단위 정밀도로 호출하고 태스크 drain·OS 종료가 이어지므로 전체 종료 완료 시각은 이후가 된다. ECS drain 실패 시 API/worker는 desired=0으로 남을 수 있지만 DB 등 EC2는 먼저 끄지 않는다. 실패는 SSM Automation 실행 이력에서 확인한다. 별도 실패 알림이나 DLQ는 이번에 추가하지 않았다.

IAM은 staging EC2 다섯 ID와 태그, staging 서비스 두 ARN으로 제한한다. 조회 API의 Resource=*는 서비스 제약상 읽기 전용에 한하며 task 조회는 staging cluster로 제한한다. Scheduler 역할은 이 Automation만 시작하고 해당 실행 역할만 전달할 수 있다. 실행 역할에는 prod 조작·시작·삭제 API를 부여하지 않는다.

## 검증·수동 시작

2026-10-29 첫 예약 실행은 01:00:11 KST에 Scheduler가 SSM을 호출했으나 `StartAutomationExecution`의 document ARN 권한 누락으로 AccessDenied가 발생했다. 종료 Automation이 생성되지 않아 EC2와 ECS는 켜진 상태로 남았다. 기존 관리자 역할의 DryRun과 automation-definition ARN만 사용한 IAM 시뮬레이션으로는 이 호출 경로를 검증하지 못했다.

Scheduler 정책에 해당 document ARN과 같은 계정·리전의 automation-execution ARN을 추가했다. Automation 타입의 `aws_ssm_document.arn`은 automation-definition ARN이므로 document ARN은 이름으로 명시한다. 다른 문서를 실행할 권한이나 EC2/ECS 조작 권한을 Scheduler에 추가하지 않았다. 실패가 Automation 생성 전이면 SSM 실행 이력이 없으므로 CloudTrail의 StartAutomationExecution 오류와 AWS/Scheduler TargetErrorCount도 확인한다. 권한 구성은 [AWS Automation IAM 예제](https://docs.aws.amazon.com/systems-manager/latest/userguide/automation-setup-identity-based-policies.html)를 참고한다.

수정 후 동일 Scheduler 역할·대상으로 일회성 DryRun 예약을 실행했다. 2026-10-29 08:25:57 KST Automation `b1abc34d-a4b7-4657-9941-92b1e6970f8c`가 Success였고 실행자는 전용 Scheduler 역할이다. 시험 스케줄은 자동 삭제됐으며 정규 01:00 스케줄은 유지한다. 전체 plan은 IAM 정책 1개 변경만 있었고 후속 plan은 No changes, 종료 코드 안전 테스트 7개 통과다. 실제 종료는 실행하지 않았으므로 전체 stop 완료는 다음 예약 실행에서 확인해야 한다.

`DryRun` 기본값은 true다. true 실행은 대상 태그·서비스 존재 여부만 확인하고 update_service/stop_instances는 호출하지 않는다. 스케줄만 명시적으로 false를 전달한다. apply 직후 실제 stop 검증을 위해 staging을 강제로 끄지 않는다.

```bash
aws ssm start-automation-execution \
  --document-name zipsai-staging-nightly-shutdown \
  --parameters 'DryRun=true' --region ap-northeast-2 --profile terraform
```

수동 시작은 `/Users/max/Desktop/zipsai script/V2 서버 관리/2-staging-켜기.command`를 사용한다. 같은 폴더의 `v2_power.py`를 2026-10-28 현재 구성에 맞게 수정했다. staging은 삭제된 replica를 제외한 EC2 다섯 대를 켜고, 로컬 복구 기록이 없으면 API=1·worker=1을 복원한다. 기존 복구 기록이 있으면 그 기록을 우선하며 prod 동작은 유지한다. EC2 상태 검사 후 DB·Redis·AI의 실제 준비를 사람이 확인하고 두 번째 yes를 입력해야 ECS를 켠다. V1 시작 스크립트는 이번 구성용이 아니다. AWS 명령을 모의 처리한 테스트 6개와 command shell 구문 검사를 통과했으며 실제 전원 조작 시험은 하지 않았다. 원본은 같은 폴더 `v2_power.py.before-20261028.bak`에 보존했다.

Terraform의 API/worker baseline은 여전히 1이다. 예약 종료 후 desired_count=0 차이는 의도된 전원 상태이며 그 시간에 staging 전체 apply를 하면 ECS를 1로 복원할 수 있다. EC2까지 켜지는 것은 아니므로 중지 시간 중 일반 apply/CD 실행을 피하고 기존 시작 절차로 의존성을 먼저 기동한다. 종료 절차와 수동 시작을 동시에 실행하지 않는다. 현재 동시 작업 감지는 원자적 잠금이 아니며 최종 재확인 뒤의 경합까지 완전히 막지는 않는다.

## 관리·Rollback

일회적으로 종료를 건너뛰려면 Scheduler 콘솔에서 해당 스케줄을 DISABLED로 변경할 수 있으나 IaC drift가 되므로 지속 변경은 `nightly-shutdown.tf`의 state를 수정해 plan/apply한다. 코드에서 state를 DISABLED로 하면 다음 예약 실행을 막지만 이미 시작된 Automation을 취소하거나 중지된 서버를 켜주지는 않는다. 다시 켜는 것은 기존 수동 시작 절차로 수행한다.

코드 파일은 `terraform/environments/staging/nightly-shutdown.tf`, `scripts/nightly_shutdown.py`, 오프라인 안전 테스트 `scripts/test_nightly_shutdown.py`다. Cloud 레포와 M15 산출물에 동일하게 보관한다. 새 노드나 서비스가 추가되면 대상·IAM·안전 검사·테스트도 함께 갱신해야 한다.
