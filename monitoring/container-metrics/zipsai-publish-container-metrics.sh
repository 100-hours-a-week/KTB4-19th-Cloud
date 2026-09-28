#!/usr/bin/env bash
set -euo pipefail

# Docker Compose Container별 CPU·메모리 사용량을 CloudWatch Custom Metric으로 전송한다.
# Host 전체 자원 지표와 함께 비교해 부하 테스트 중 어떤 Container가 먼저 포화되는지 확인한다.

readonly AWS_REGION="${AWS_REGION:-ap-northeast-2}"
readonly METRIC_NAMESPACE="Zipsai/Container"
readonly LOCK_FILE="/run/zipsai-container-metrics.lock"

# Compose project 이름과 서비스 이름으로 만들어지는 운영 Container 이름이다.
readonly SERVICES=(backend ai-api embedding mysql qdrant nginx)

exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

to_bytes() {
  local memory_value="$1"
  local number unit multiplier

  if [[ ! "$memory_value" =~ ^([0-9]+([.][0-9]+)?)([KMGTP]?i?B)$ ]]; then
    return 1
  fi

  number="${BASH_REMATCH[1]}"
  unit="${BASH_REMATCH[3]}"

  case "$unit" in
    B) multiplier=1 ;;
    KB) multiplier=1000 ;;
    MB) multiplier=1000000 ;;
    GB) multiplier=1000000000 ;;
    TB) multiplier=1000000000000 ;;
    KiB) multiplier=1024 ;;
    MiB) multiplier=1048576 ;;
    GiB) multiplier=1073741824 ;;
    TiB) multiplier=1099511627776 ;;
    *) return 1 ;;
  esac

  awk -v value="$number" -v factor="$multiplier" 'BEGIN { printf "%.0f\n", value * factor }'
}

for service in "${SERVICES[@]}"; do
  container="zipsai-${service}-1"

  if ! stats="$(docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' "$container" 2>/dev/null)"; then
    logger -t zipsai-container-metrics "container not found: ${container}"
    continue
  fi

  cpu_percent="${stats%%|*}"
  memory_usage="${stats#*|}"
  memory_value="${memory_usage%% / *}"
  cpu_value="${cpu_percent%%%}"

  if [[ ! "$cpu_value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    logger -t zipsai-container-metrics "invalid CPU usage for ${container}: ${cpu_percent}"
    continue
  fi

  if ! memory_bytes="$(to_bytes "$memory_value")"; then
    logger -t zipsai-container-metrics "invalid memory usage for ${container}: ${memory_value}"
    continue
  fi

  aws cloudwatch put-metric-data \
    --region "$AWS_REGION" \
    --namespace "$METRIC_NAMESPACE" \
    --metric-name CpuUsagePercent \
    --unit Percent \
    --value "$cpu_value" \
    --dimensions "Service=${service}" \
    --no-cli-pager

  aws cloudwatch put-metric-data \
    --region "$AWS_REGION" \
    --namespace "$METRIC_NAMESPACE" \
    --metric-name MemoryUsageBytes \
    --unit Bytes \
    --value "$memory_bytes" \
    --dimensions "Service=${service}" \
    --no-cli-pager

  logger -t zipsai-container-metrics "service=${service} cpu_percent=${cpu_value} memory_bytes=${memory_bytes}"
done
