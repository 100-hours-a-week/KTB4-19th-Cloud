require_bootstrap_tools() {
  local tool
  for tool in aws kubectl helm jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      printf 'Required command missing from PATH: %s\n' "$tool" >&2
      return 1
    fi
  done
}

build_bootstrap_chart() {
  local chart_dir=$1 repo_name=$2 repo_url=$3
  helm repo add "$repo_name" "$repo_url" --force-update
  helm dependency build "$chart_dir" --skip-refresh
}
