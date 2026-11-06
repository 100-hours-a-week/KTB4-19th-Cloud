# 공통 ACM 인증서와 DNS 검증 레코드 관리

## 목적과 최종 구조

이슈 #22에서 prod·staging을 공통 인증서로 전환했다. 이슈 #24에서는 연결이 해제된 개별 인증서와 불필요한 검증 레코드를 정리하고, 공통 인증서 갱신에 필요한 CNAME의 관리 주체를 prod에서 shared로 옮긴다.

| shared 리소스 | 범위 |
|---|---|
| `aws_acm_certificate.cloudfront` | us-east-1, `zipsai.co.kr` + `*.zipsai.co.kr` |
| `aws_acm_certificate.api_alb` | ap-northeast-2, `*.zipsai.co.kr` |
| `aws_route53_record.certificate_validation` | 두 인증서가 공통으로 사용하는 검증 CNAME 한 개 |

prod·staging은 shared output ARN만 참조한다. 도메인 A/AAAA, CloudFront alias, ALB listener, ECS 실행 수는 이번 정리 대상이 아니다. 와일드카드는 한 단계 하위 도메인만 포함한다.

## 적용 순서

1. 두 리전의 모든 인증서 `InUseBy`를 조회한다. 공통 인증서만 연결되어 있고 삭제할 개별 인증서는 모두 미사용이어야 한다.
2. 각 root의 state를 접근 제한된 위치에 백업하고, 실제 ECS desired count를 입력하여 전체 plan을 생성한다. 백업과 raw plan에는 비밀값이 포함될 수 있으므로 커밋하지 않는다.
3. prod plan에서 apex CNAME이 `moved` → `removed`의 `destroy=false`로 **관리 해제만** 되는지 확인한다. 그 외 삭제 대상은 미사용 개별 인증서·validation·불필요한 검증 CNAME이어야 한다.
4. **prod를 먼저 apply한다.** 공통 CNAME의 실제 이름·값·TTL은 그대로 남고 기존 prod state에서만 빠진다. 이때 shared apply는 아직 하지 않는다.
5. shared plan의 import ID와 기존 CNAME이 일치하는지 확인한 뒤 apply한다. 기존 CNAME을 import하며 DNS를 새로 만들거나 변경하지 않는다. 두 validation은 이 CNAME을 명시적으로 참조한다.
6. staging plan을 다시 확인하고 apply하여 나머지 미사용 개별 인증서와 검증 레코드를 정리한다.
7. ACM 인증서 총 2개, 각 연결 유지, 공통 CNAME 일치, 모든 대상 도메인의 실제 TLS 인증서·HTTP 응답을 검증한다. 각 root의 후속 전체 plan이 No changes인지 확인한다.

prod의 `moved`/`removed`와 shared `import`는 관리 이관 이력으로 남긴다. import 전에 두 state가 같은 레코드를 동시에 관리하게 하지 않는다. 공통 CNAME에는 실수로 삭제하지 않도록 `prevent_destroy`를 둔다.

## 실패 시 복구

- prod apply 후 shared import가 실패해도 공통 CNAME은 삭제되지 않는다. CNAME의 실제 값이 유지되는지 확인하고 shared import를 재시도한다. prod의 이전 코드로 apply하여 같은 레코드를 다시 생성하려 하지 않는다.
- 인증서는 현재 공통 ARN으로 계속 연결된다. 삭제한 개별 인증서를 복구하려면 재발급이 필요하므로 예전 커밋을 무조건 apply하지 않는다.
- state 백업 복원은 실제 AWS 변경과 충돌할 수 있다. 현재 리소스와 state 차이를 먼저 확인하고 필요한 주소만 복구한다.

## 검증 기록

2026-11-06 이슈 #24 적용을 완료했다.

- prod: 미사용 인증서 3개·전용 CNAME 3개·validation 대기 객체 3개 삭제, 공통 CNAME 1개는 삭제 없이 관리 해제.
- shared: 기존 CNAME 1개 import, validation 대기 객체 2개 재생성. 실제 공통 인증서 2개는 그대로 유지.
- staging: 미사용 인증서 2개·전용 CNAME 2개·validation 대기 객체 2개 삭제.
- 최종 ACM: 서울 1개·버지니아 1개, 둘 다 ISSUED 및 각 prod·staging 2곳에 연결.
- 공통 CNAME 이름·값·TTL 보존, shared state에서만 관리.
- 운영·스테이징 프론트 및 API 6개 도메인의 실제 TLS 지문 일치와 HTTP 200 확인.
- shared·prod·staging 후속 전체 plan 모두 No changes.

더 자세한 실행 기록은 `운영-기록/작업-기록.md`에 남겼다. 검증 당시 ECS 실행 수는 prod API 2/worker 1, staging API 1/worker 1이다. 향후 plan 시에는 현재 실행 수를 다시 확인한다.

## 참고

- [Terraform state 간 리소스 이관](https://developer.hashicorp.com/terraform/language/state/refactor)
- [ACM DNS 검증과 공통 검증 CNAME](https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html)
