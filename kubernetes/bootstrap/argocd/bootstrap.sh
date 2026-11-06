#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'Usage: bash %s <kube-context>\n' "$0" >&2
  exit 2
fi

context=$1
bootstrap_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
chart_dir="$bootstrap_dir/../argocd"
cluster="$(aws eks describe-cluster --region ap-northeast-2 --name zipsai-v3-eks --query cluster --output json)"
endpoint="$(jq -er '.endpoint | select(startswith("https://"))' <<< "$cluster")"
subnets="$(jq -ec '.resourcesVpcConfig.subnetIds | select(length == 2)' <<< "$cluster")"
context_endpoint="$(kubectl config view -o json | jq -er --arg context "$context" '
  (.contexts[] | select(.name == $context).context.cluster) as $cluster
  | .clusters[] | select(.name == $cluster).cluster.server
')"

if [[ "$context_endpoint" != "$endpoint" ]]; then
  printf 'The selected kube context does not point to the zipsai-v3-eks API.\n' >&2
  exit 1
fi

# Cilium must already be running before Argo CD takes over its configuration.
kubectl --context "$context" -n kube-system rollout status daemonset/cilium --timeout=5m
kubectl --context "$context" -n kube-system rollout status deployment/cilium-operator --timeout=5m

# Once installed, the argocd Application manages upgrades from Git.
server_deployment="$(kubectl --context "$context" -n argocd get deployment argocd-server --ignore-not-found -o name)"
if [[ -z "$server_deployment" ]]; then
  helm dependency build "$chart_dir"
  helm upgrade --install argocd "$chart_dir" --kube-context "$context" \
    --namespace argocd --create-namespace --wait --timeout 10m
fi

kubectl --context "$context" wait --for=condition=Established --timeout=2m \
  crd/applications.argoproj.io crd/appprojects.argoproj.io
kubectl --context "$context" -n argocd rollout status deployment/argocd-server --timeout=5m
kubectl --context "$context" apply -f "$bootstrap_dir/root-project.yaml"

# Match the cluster-specific overrides used during the initial Cilium installation.
kubectl --context "$context" create --dry-run=client -f "$bootstrap_dir/root-application.yaml" -o json |
  jq --arg host "${endpoint#https://}" --argjson subnets "$subnets" '
    .spec.source.helm.valuesObject.cilium = {
      enabled: true,
      apiHost: $host,
      subnetIds: $subnets
    }
  ' |
  kubectl --context "$context" apply -f -
