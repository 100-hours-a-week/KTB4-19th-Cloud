#!/usr/bin/env bash
set -euo pipefail

# This host uses the standard AL2023 x86_64 AMI.
export PATH=/usr/local/bin:/usr/bin:/bin
packages=(git jq tar gzip)
if [[ "$(aws --version 2>/dev/null || true)" != aws-cli/2.* ]]; then
  packages+=(awscli-2)
fi
dnf install -y "${packages[@]}"

kubectl_url=https://s3.us-west-2.amazonaws.com/amazon-eks/1.36.2/2026-07-05/bin/linux/amd64/kubectl
kubectl_sha256=485546d8b76a97f01f63c36716b6412a87a89c6eed3d4495041660ff6b6b62d4
helm_archive=helm-v4.2.3-linux-amd64.tar.gz
helm_sha256=e9b88b4ee95b18c706839c28d3a0220e5bc470e9cd9262410c90793c45ff8b7c

work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT
cd "$work_dir"

curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 --max-time 120 \
  --output kubectl "$kubectl_url"
printf '%s  %s\n' "$kubectl_sha256" kubectl | sha256sum --check -
curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 --max-time 120 \
  --output "$helm_archive" "https://get.helm.sh/$helm_archive"
printf '%s  %s\n' "$helm_sha256" "$helm_archive" | sha256sum --check -
tar -xzf "$helm_archive" linux-amd64/helm
install -m 0755 kubectl linux-amd64/helm /usr/local/bin/

aws --version
kubectl version --client
helm version --short
jq --version
