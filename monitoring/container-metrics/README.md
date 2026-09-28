# Container Resource Metrics

Docker Compose로 실행되는 Container별 CPU·메모리 사용량을 CloudWatch에 전송한다.
EC2 전체 CPU·메모리 지표와 k6 부하 테스트 결과를 함께 비교해 병목 후보를 찾는 용도다.

## 수집 대상과 지표

| 대상 | CloudWatch Namespace | Metric | Dimension | Unit |
| --- | --- | --- | --- | --- |
| `backend`, `ai-api`, `embedding`, `mysql`, `qdrant`, `nginx` | `Zipsai/Container` | `CpuUsagePercent` | `Service` | Percent |
| 동일 | `Zipsai/Container` | `MemoryUsageBytes` | `Service` | Bytes |

`zipsai-container-metrics.timer`는 1분마다 Service를 실행한다. Script는 `docker stats --no-stream`의 CPU 사용률과 메모리 사용량을 읽어 지표를 전송한다. Container가 배포 중이거나 중지되어 존재하지 않으면 해당 Container만 건너뛰고 다음 대상 수집을 계속한다.

## EC2 설치와 확인

Cloud CD가 아래 파일을 EC2에 설치하고 Timer를 활성화한다.

| 저장소 파일 | EC2 설치 위치 |
| --- | --- |
| `zipsai-publish-container-metrics.sh` | `/usr/local/bin/zipsai-publish-container-metrics.sh` |
| `zipsai-container-metrics.service` | `/etc/systemd/system/zipsai-container-metrics.service` |
| `zipsai-container-metrics.timer` | `/etc/systemd/system/zipsai-container-metrics.timer` |

```bash
sudo systemctl status zipsai-container-metrics.timer --no-pager
sudo systemctl status zipsai-container-metrics.service --no-pager
sudo journalctl -u zipsai-container-metrics.service --no-pager -n 30
```

Timer의 `active (waiting)` 상태와 oneshot Service의 `inactive (dead)` 상태는 정상이다. CloudWatch 콘솔에서는 `Zipsai/Container` Namespace에서 `Service` Dimension을 선택해 각 지표를 확인한다.
