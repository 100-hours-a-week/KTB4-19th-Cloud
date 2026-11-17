# V3 자동 동기화 일시정지 — 전체 중지의 첫 단계

`maintenance.suspendAutoSync`는 하위 Argo CD Application의 자동 동기화를 제어한다. 기본값은 `false`이며 기존 렌더링을 유지한다. `true`이면 공통 구성과 staging Application의 `syncPolicy.automated` 선언을 제거한다. prod Application은 원래의 수동 Sync 정책을 유지한다.

Application·워크로드·PVC·Ingress를 삭제하거나 replica 수를 바꾸지 않는다. v3-root는 계속 동작하며 이 설정을 하위 Application에 반영한다. 수동 Sync와 이미 진행 중인 Sync는 차단하지 않는다. HPA, Karpenter, Reloader 등 실행 중인 Controller도 이 옵션만으로 정지하지 않는다.

## 적용 준비와 활성화

1. 변경을 검토·커밋·push하고 Cloud main에 반영한다. 기본 설정만 반영하면 자동 동기화 정책은 바뀌지 않는다.
2. 운영자가 중지 준비를 시작할 때 v3-root의 `spec.source.helm.valueFiles`에 마지막 파일로 `values-maintenance.yaml`을 추가한다. 현재 확인한 파일 목록은 다음과 같다.

   ```yaml
   valueFiles:
     - values.yaml
     - values-platform.yaml
     - values-maintenance.yaml
   ```

3. 기존 `valuesObject`의 VPC·Cilium API·서브넷·보안 그룹·계정 값을 유지한다. Helm 우선순위상 valuesObject에 `maintenance.suspendAutoSync`를 별도로 넣었다면 그 값이 파일보다 우선한다.
4. v3-root가 변경을 반영한 후 하위 Application의 `spec.syncPolicy.automated`가 없어졌고 진행 중인 Sync가 없는지 확인한다. 실제 리소스 수나 replica 수는 이 단계에서 바꾸지 않는다.

Root Application은 Bootstrap 선언으로 등록되어 있으므로, 활성화는 운영자가 현재 Root의 입력 파일 목록에 위 선언을 반영하는 별도 작업이다. Git에 파일을 추가하는 것만으로 활성화되지 않는다. Bootstrap을 다시 적용하거나 Root를 재생성할 때에도 현재 중지/운영 입력 목록과 기존 valuesObject를 보존한다.

## 복원

노드·데이터 서비스·워크로드를 복원하는 절차에 따라 준비한 뒤, Root의 입력 파일 목록에서 `values-maintenance.yaml`만 제거한다. 또는 더 높은 우선순위의 입력에서 `maintenance.suspendAutoSync: false`를 명시한다. v3-root가 공통 구성과 staging의 기존 자동 동기화 정책을 복원한다. prod는 계속 수동 Sync다. 자동 복원을 재개하기 전에 Git의 목표 상태가 의도한 복원 상태인지 확인한다.

## 다음 단계와 경계

이 옵션은 전체 중지 기능의 첫 단계다. 다음으로 실행 중인 워크로드·예약 작업·자동 확장을 제어하고, 데이터 및 PVC 보존을 확인한 뒤 Karpenter 노드와 기본 노드, 독립 EC2를 순서대로 중지하는 별도 구성이 필요하다. 이 변경만으로 전체 중지가 완료됐다고 판단하지 않는다.

`applications.* = false`, `stateful.*Enabled = false`, `karpenter.enabled = false`는 일시정지 옵션이 아니다. Application 선언을 제거하는 기존 활성화 옵션을 중지 용도로 대체 사용하지 않는다.

## 로컬 검증

현재 플랫폼 입력과 런타임 연결값 구조를 사용해 Helm lint 및 렌더링을 비교했다. 기본 모드는 변경 전과 동일한 리소스를 생성한다. 일시정지 모드는 리소스 목록과 다른 속성을 유지하면서 기존 자동 동기화 대상 19개의 automated 선언만 제거한다. 수동 Sync 대상 7개는 그대로 유지한다. 이 결과는 실제 Cluster 반영 검증을 대신하지 않는다.
