#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 || ( "$1" != "prepare" && "$1" != "install" ) ]]; then
  printf 'Usage: bash %s <prepare|install> <kube-context>\n' "$0" >&2
  exit 2
fi

action=$1
context=$2
bootstrap_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
chart_dir="$bootstrap_dir/../addons/cilium"
source "$bootstrap_dir/common.sh"
require_bootstrap_tools
cluster="$(aws eks describe-cluster --region ap-northeast-2 --name zipsai-v3-eks --query cluster --output json)"
endpoint="$(jq -er '.endpoint | select(startswith("https://"))' <<< "$cluster")"
context_endpoint="$(kubectl config view -o json | jq -er --arg context "$context" '
  (.contexts[] | select(.name == $context).context.cluster) as $cluster
  | .clusters[] | select(.name == $cluster).cluster.server
')"

if [[ "$context_endpoint" != "$endpoint" ]]; then
  printf 'The selected kube context does not point to the zipsai-v3-eks API.\n' >&2
  exit 1
fi

selector="$(kubectl --context "$context" -n kube-system get daemonset aws-node -o json |
  jq -r '.spec.template.spec.nodeSelector["io.cilium/aws-node-enabled"] // ""')"

if [[ "$action" == "prepare" ]]; then
  if [[ "$selector" == "true" ]]; then
    exit 0
  fi
  if ! kubectl --context "$context" get nodes -o json | jq -e '.items | length == 0' >/dev/null; then
    printf 'Prepare aws-node before any nodes join. Refusing to change an active CNI.\n' >&2
    exit 1
  fi
  # Run before enabling Managed Node Groups so aws-node never claims a V3 node.
  kubectl --context "$context" -n kube-system patch daemonset aws-node --type=strategic \
    -p '{"spec":{"template":{"spec":{"nodeSelector":{"io.cilium/aws-node-enabled":"true"}}}}}'
  exit 0
fi

if [[ "$selector" != "true" ]]; then
  printf 'Run the prepare step before installing Cilium.\n' >&2
  exit 1
fi

subnet_ids="$(jq -er '.resourcesVpcConfig.subnetIds | select(length == 2) | join(",")' <<< "$cluster")"
build_bootstrap_chart "$chart_dir" zipsai-v3-cilium https://helm.cilium.io
# Apply manifests without waiting for Pods. Node groups and the Pod Identity Agent
# can be enabled after this command on the first deployment.
helm upgrade --install cilium "$chart_dir" --kube-context "$context" --namespace kube-system \
  --set-string "cilium.k8sServiceHost=${endpoint#https://}" \
  --set "cilium.k8sServicePort=443" \
  --set-string "cilium.eni.subnetIDsFilter={${subnet_ids}}"
