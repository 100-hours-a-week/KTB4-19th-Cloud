#!/usr/bin/env bash
set -Eeuo pipefail

: "${NODE_EXPORTER_VERSION:?NODE_EXPORTER_VERSION must be set}"
: "${MYSQLD_EXPORTER_VERSION:?MYSQLD_EXPORTER_VERSION must be set}"

readonly architecture="amd64"
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

install_release() {
  local project="$1"
  local version="$2"
  local binary="$3"
  local archive="${project}-${version}.linux-${architecture}.tar.gz"
  local release_url="https://github.com/prometheus/${project}/releases/download/v${version}"

  curl --fail --silent --show-error --location \
    "${release_url}/${archive}" \
    --output "${work_dir}/${archive}"
  curl --fail --silent --show-error --location \
    "${release_url}/sha256sums.txt" \
    --output "${work_dir}/${project}-sha256sums.txt"

  (
    cd "${work_dir}"
    grep " ${archive}$" "${project}-sha256sums.txt" | sha256sum --check --strict -
  )

  tar -xzf "${work_dir}/${archive}" -C "${work_dir}"
  sudo install -o root -g root -m 0755 \
    "${work_dir}/${project}-${version}.linux-${architecture}/${binary}" \
    "/usr/local/bin/${binary}"
}

install_release "node_exporter" "${NODE_EXPORTER_VERSION}" "node_exporter"
install_release "mysqld_exporter" "${MYSQLD_EXPORTER_VERSION}" "mysqld_exporter"

if ! id node_exporter >/dev/null 2>&1; then
  sudo useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter
fi

if ! id mysqld_exporter >/dev/null 2>&1; then
  sudo useradd --system --no-create-home --shell /usr/sbin/nologin mysqld_exporter
fi

sudo install -d -o root -g mysqld_exporter -m 0750 /etc/zipsai
sudo install -o root -g root -m 0644 \
  /tmp/zipsai-node-exporter.service \
  /etc/systemd/system/node_exporter.service
sudo install -o root -g root -m 0644 \
  /tmp/zipsai-mysqld-exporter.service \
  /etc/systemd/system/mysqld_exporter.service

sudo systemctl daemon-reload
sudo systemctl enable node_exporter.service
sudo systemctl enable mysqld_exporter.service

sudo rm -f \
  /tmp/zipsai-node-exporter.service \
  /tmp/zipsai-mysqld-exporter.service
