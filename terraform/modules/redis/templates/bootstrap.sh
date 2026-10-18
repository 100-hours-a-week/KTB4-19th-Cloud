#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl unzip docker.io
systemctl enable --now docker
if ! command -v aws >/dev/null 2>&1; then
  bootstrap_dir="$(mktemp -d)"
  curl --fail --silent --show-error --retry 5 https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o "$bootstrap_dir/awscliv2.zip"
  unzip -q "$bootstrap_dir/awscliv2.zip" -d "$bootstrap_dir"
  "$bootstrap_dir/aws/install"
fi
if ! snap list amazon-ssm-agent >/dev/null 2>&1; then
  snap install amazon-ssm-agent --classic
fi
snap start amazon-ssm-agent
