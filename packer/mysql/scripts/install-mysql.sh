#!/usr/bin/env bash
set -Eeuo pipefail

: "${MYSQL_VERSION:?MYSQL_VERSION must be set}"

readonly mysql_package_version="${MYSQL_VERSION}-1ubuntu24.04"

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  gnupg

ssm_service=""
for candidate in \
  amazon-ssm-agent.service \
  snap.amazon-ssm-agent.amazon-ssm-agent.service; do
  if systemctl list-unit-files "${candidate}" --no-legend 2>/dev/null | grep -q "^${candidate}"; then
    ssm_service="${candidate}"
    break
  fi
done

if [[ -z "${ssm_service}" ]]; then
  sudo snap install amazon-ssm-agent --classic
  ssm_service="snap.amazon-ssm-agent.amazon-ssm-agent.service"
fi

sudo systemctl enable --now "${ssm_service}"

curl --fail --silent --show-error --location \
  "https://repo.mysql.com/RPM-GPG-KEY-mysql-2025" \
  --output "${work_dir}/mysql-release-key.asc"

gpg --batch --yes --dearmor \
  --output "${work_dir}/mysql-release-key.gpg" \
  "${work_dir}/mysql-release-key.asc"
sudo install -o root -g root -m 0644 \
  "${work_dir}/mysql-release-key.gpg" \
  /usr/share/keyrings/mysql-release-key.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/mysql-release-key.gpg] https://repo.mysql.com/apt/ubuntu/ noble mysql-8.4-lts" \
  | sudo tee /etc/apt/sources.list.d/mysql.list >/dev/null

sudo apt-get update
sudo sh -c 'printf "#!/bin/sh\nexit 101\n" > /usr/sbin/policy-rc.d'
sudo chmod 0755 /usr/sbin/policy-rc.d
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  "mysql-server=${mysql_package_version}"
sudo rm -f /usr/sbin/policy-rc.d

sudo systemctl stop mysql.service 2>/dev/null || true
if [[ -d /var/lib/mysql ]]; then
  sudo find /var/lib/mysql -mindepth 1 -delete
fi

sudo install -d -o mysql -g mysql -m 0750 /data
sudo install -d -o mysql -g mysql -m 0750 /var/log/mysql
sudo install -o root -g root -m 0644 \
  /tmp/zipsai-my.cnf \
  /etc/mysql/mysql.conf.d/zipsai.cnf

sudo install -d -o root -g root -m 0755 /etc/systemd/system/mysql.service.d
sudo install -o root -g root -m 0644 \
  /tmp/zipsai-mysql-service-override.conf \
  /etc/systemd/system/mysql.service.d/override.conf

sudo install -d -o root -g root -m 0755 /etc/apparmor.d/local
sudo install -o root -g root -m 0644 \
  /tmp/zipsai-apparmor-mysqld.local \
  /etc/apparmor.d/local/usr.sbin.mysqld

sudo systemctl daemon-reload
sudo systemctl enable mysql.service

sudo rm -f \
  /tmp/zipsai-my.cnf \
  /tmp/zipsai-mysql-service-override.conf \
  /tmp/zipsai-apparmor-mysqld.local
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

