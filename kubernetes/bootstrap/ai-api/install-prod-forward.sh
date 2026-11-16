#!/usr/bin/env bash
set -euo pipefail

# Run on the V3 management EC2 after its zipsai-v3 kube context is configured.
if [[ $(id -u) -ne 0 ]]; then
  echo 'Run with sudo bash kubernetes/bootstrap/ai-api/install-prod-forward.sh' >&2
  exit 1
fi
sudo -u ssm-user env KUBECONFIG=/home/ssm-user/.kube/config \
  /usr/local/bin/kubectl --context=zipsai-v3 -n prod get service ai-api >/dev/null

unit_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
install -m 0644 "$unit_dir/zipsai-v3-prod-ai-api-forward.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now zipsai-v3-prod-ai-api-forward.service
systemctl restart zipsai-v3-prod-ai-api-forward.service
for attempt in {1..20}; do
  if curl --fail --silent --show-error --max-time 3 http://127.0.0.1:18000/liveness; then
    printf '\nV3 prod AI API loopback forward is ready.\n'
    exit 0
  fi
  sleep 2
done
systemctl status zipsai-v3-prod-ai-api-forward.service --no-pager
exit 1
