#!/usr/bin/env bash
set -Eeuo pipefail

: "${MYSQL_VERSION:?MYSQL_VERSION must be set}"
: "${NODE_EXPORTER_VERSION:?NODE_EXPORTER_VERSION must be set}"
: "${MYSQLD_EXPORTER_VERSION:?MYSQLD_EXPORTER_VERSION must be set}"

test "$(uname -m)" = "x86_64"
test -x /usr/sbin/mysqld
/usr/sbin/mysqld --version | grep -F "Ver ${MYSQL_VERSION}"
dpkg-query -W -f='${Version}\n' mysql-community-server \
  | grep -Fx "${MYSQL_VERSION}-1ubuntu24.04"

ssm_service=""
for candidate in \
  amazon-ssm-agent.service \
  snap.amazon-ssm-agent.amazon-ssm-agent.service; do
  if systemctl list-unit-files "${candidate}" --no-legend 2>/dev/null | grep -q "^${candidate}"; then
    ssm_service="${candidate}"
    break
  fi
done

test -n "${ssm_service}"
systemctl is-enabled --quiet "${ssm_service}"
systemctl is-active --quiet "${ssm_service}"
systemctl is-enabled --quiet mysql.service
systemctl is-enabled --quiet node_exporter.service
systemctl is-enabled --quiet mysqld_exporter.service
test "$(systemctl is-active mysql.service)" = "inactive"

/usr/local/bin/node_exporter --version 2>&1 | grep -F "version ${NODE_EXPORTER_VERSION}"
/usr/local/bin/mysqld_exporter --version 2>&1 | grep -F "version ${MYSQLD_EXPORTER_VERSION}"

sudo systemd-analyze verify mysql.service
sudo systemd-analyze verify node_exporter.service
sudo systemd-analyze verify mysqld_exporter.service
test -f /etc/mysql/mysql.conf.d/zipsai.cnf
test -f /etc/systemd/system/mysql.service.d/override.conf
test ! -e /data/mysql/auto.cnf

