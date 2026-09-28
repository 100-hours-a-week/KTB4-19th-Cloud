# EC2 Host Metrics

EC2 전체 메모리 사용률과 Root 파일시스템 사용률을 CloudWatch Agent로 전송한다. Docker Compose Container별 지표는 `../container-metrics/`의 별도 수집기가 담당한다.

| CloudWatch Namespace | Metric | Dimension | 의미 |
| --- | --- | --- | --- |
| `CWAgent` | `mem_used_percent` | `InstanceId` | EC2 전체 메모리 사용률 |
| `CWAgent` | `disk_used_percent` | `InstanceId`, `path=/` | Root 파일시스템 사용률 |

`amazon-cloudwatch-agent.json`은 60초마다 두 지표를 수집한다. Cloud CD는 Cloud Commit에 이 파일이 존재하는 경우에만 Agent를 설치 또는 갱신하고, 설정을 적용한 뒤 Agent를 재시작한다.

## EC2 확인

```bash
sudo systemctl status amazon-cloudwatch-agent --no-pager
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status
sudo tail -n 50 /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log
```

CloudWatch 콘솔에서는 `CWAgent` Namespace에서 해당 InstanceId를 선택한다. Root 디스크는 `path=/` 차원을 함께 선택한다.
