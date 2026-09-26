#!/usr/bin/env bash
set -euo pipefail

# Docker가 관리하는 누적 RestartCount의 증가분만 CloudWatch Custom Metric으로 전송한다.
# 최초 실행과 컨테이너 교체 후에는 기존 누적값을 경보로 보내지 않는다.

readonly AWS_REGION="${AWS_REGION:-ap-northeast-2}"
readonly METRIC_NAMESPACE="Zipsai/Container"
readonly METRIC_NAME="RestartCount"
readonly STATE_DIR="${STATE_DIR:-/var/lib/zipsai/restart-metrics}"
readonly LOCK_FILE="/run/zipsai-restart-metrics.lock"

# Compose project 이름과 서비스 이름으로 만들어지는 운영 컨테이너 이름이다.
readonly SERVICES=(backend ai-api embedding mysql qdrant nginx)

mkdir -p "$STATE_DIR"

exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

for service in "${SERVICES[@]}"; do
  container="zipsai-${service}-1"
  state_file="${STATE_DIR}/${service}"

  if ! current_count="$(docker inspect --format '{{.RestartCount}}' "$container" 2>/dev/null)"; then
    logger -t zipsai-restart-metrics "container not found: ${container}"
    continue
  fi

  if [[ ! "$current_count" =~ ^[0-9]+$ ]]; then
    logger -t zipsai-restart-metrics "invalid restart count for ${container}: ${current_count}"
    continue
  fi

  previous_count=0
  initialized=false
  if [[ -f "$state_file" ]]; then
    previous_count="$(<"$state_file")"
    initialized=true
  fi

  # 컨테이너 재생성 시 RestartCount가 0으로 초기화될 수 있다.
  # 이 경우 기존 컨테이너의 횟수를 새 컨테이너 장애로 해석하지 않는다.
  restart_delta=0
  if [[ "$initialized" == true ]] && (( current_count >= previous_count )); then
    restart_delta=$((current_count - previous_count))
  fi

  aws cloudwatch put-metric-data \
    --region "$AWS_REGION" \
    --namespace "$METRIC_NAMESPACE" \
    --metric-name "$METRIC_NAME" \
    --unit Count \
    --value "$restart_delta" \
    --dimensions "Service=${service}" \
    --no-cli-pager

  printf '%s\n' "$current_count" >"$state_file"
  logger -t zipsai-restart-metrics "service=${service} restart_delta=${restart_delta} restart_count=${current_count}"
done
