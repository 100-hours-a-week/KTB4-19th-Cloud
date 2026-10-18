#!/usr/bin/env python3
"""Manage V1 exporters only; never recreate application/MySQL containers."""
import configparser
import fcntl
import ipaddress
import json
import os
from pathlib import Path
import re
import stat
import tempfile
import time
import urllib.request

import configure_mysql_exporter as common

SafeError = common.SafeError
CONFIG = Path('/etc/zipsai/mysql-exporter.cnf')
COMPOSE = Path('/opt/zipsai-monitoring/compose.json')
MYSQL = 'zipsai-mysql-1'
NETWORK = 'zipsai_service-tier'
IMAGES = {'mysql-exporter': 'prom/mysqld-exporter:v0.20.0',
          'node-exporter': 'prom/node-exporter:v1.9.1'}


def inspect(name):
    result = common.command(['docker', 'inspect', name], check=False)
    if result.returncode:
        # Distinguish a missing container from a broken Docker connection.
        common.command(['docker', 'info', '--format', '{{.ServerVersion}}'])
        return None
    return json.loads(result.stdout)[0]


def protected_state():
    ids = common.command(['docker', 'ps', '-aq']).stdout.split()
    containers = json.loads(common.command(['docker', 'inspect', *ids]).stdout) if ids else []
    return {c['Name']: [c['Id'], c['State']['StartedAt'], c['State']['Running']]
            for c in containers if (c['Config'].get('Labels') or {}).get(
                'com.docker.compose.service') not in IMAGES}


def mysql(sql, password=None):
    # Environment inheritance avoids putting a password in command-line arguments.
    if password is None:
        container = inspect(MYSQL)
        values = dict(item.split('=', 1) for item in container['Config']['Env'] if '=' in item)
        password = values.get('MYSQL_ROOT_PASSWORD')
        if not password:
            raise SafeError('mysql_root_password_unavailable')
        options = ['--protocol=socket', '--user=root']
    else:
        options = ['--protocol=tcp', '--host=mysql', '--user=mysqld_exporter']
    env = os.environ.copy()
    env['MYSQL_PWD'] = password
    return common.command(['docker', 'exec', '-i', '-e', 'MYSQL_PWD', MYSQL,
                           'mysql', '--no-defaults', '--batch', '--skip-column-names',
                           '--connect-timeout=5', *options], sql=sql, env=env).stdout.strip()


def verify_account(password):
    identity = mysql('SELECT CURRENT_USER();', password)
    if identity != 'mysqld_exporter@%':
        raise SafeError('unexpected_authenticated_account')
    if mysql("SELECT account_locked,max_user_connections FROM mysql.user "
             "WHERE user='mysqld_exporter' AND host='%';") != 'N\t3':
        raise SafeError('existing_account_limits_mismatch')
    grants = mysql('SHOW GRANTS FOR CURRENT_USER;', password).splitlines()
    match = re.fullmatch(r'GRANT (.+) ON \*\.\* TO .+', grants[0]) if len(grants) == 1 else None
    if (not match or set(match[1].split(', ')) != {'SELECT', 'PROCESS', 'REPLICATION CLIENT'}
            or 'WITH GRANT OPTION' in grants[0]):
        raise SafeError('existing_account_grants_mismatch')


def ensure_account(password):
    hosts = mysql("SELECT host FROM mysql.user WHERE user='mysqld_exporter';").splitlines()
    if hosts:
        if hosts != ['%']:
            raise SafeError('unexpected_exporter_accounts')
        verify_account(password)
        return False
    if mysql('SELECT @@GLOBAL.read_only,@@GLOBAL.super_read_only;') != '0\t0':
        raise SafeError('account_missing_on_readonly_node')
    mysql("SET SESSION sql_log_bin=0; SET SESSION sql_mode='NO_BACKSLASH_ESCAPES'; "
          "CREATE USER 'mysqld_exporter'@'%' IDENTIFIED BY " + common.sql_literal(password)
          + " WITH MAX_USER_CONNECTIONS 3; GRANT SELECT,PROCESS,REPLICATION CLIENT "
          "ON *.* TO 'mysqld_exporter'@'%';")
    verify_account(password)
    return True


def parse_config(text):
    parser = configparser.RawConfigParser()
    parser.read_string(text)
    if parser.get('client', 'host') != 'mysql':
        raise SafeError('existing_config_host_mismatch')
    if parser.get('client', 'port', fallback='3306') != '3306':
        raise SafeError('existing_config_port_mismatch')
    if parser.get('client', 'protocol', fallback='tcp') != 'tcp':
        raise SafeError('existing_config_protocol_mismatch')
    # Reuse native MySQL quoting/parser without changing its global constants.
    parser.set('client', 'host', '127.0.0.1')
    import io
    stream = io.StringIO()
    parser.write(stream)
    return common.config_password(stream.getvalue())


def check_config(password):
    if CONFIG.is_symlink():
        raise SafeError('config_symlink_rejected')
    if CONFIG.exists():
        info = CONFIG.stat()
        if (not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o600
                or info.st_uid != 65534 or info.st_gid != 65534):
            raise SafeError('existing_config_permissions_mismatch')
        if parse_config(CONFIG.read_text()) != password:
            raise SafeError('existing_config_password_mismatch')


def exclusive_file(path, body, mode, uid=0, gid=0):
    if path.is_symlink():
        raise SafeError('symlink_rejected')
    if path.exists():
        if path.read_text() != body:
            raise SafeError('existing_managed_file_mismatch')
        info = path.stat()
        if (stat.S_IMODE(info.st_mode), info.st_uid, info.st_gid) != (mode, uid, gid):
            raise SafeError('existing_managed_file_permissions_mismatch')
        return False
    path.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.exporter-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            os.fchmod(stream.fileno(), mode)
            os.fchown(stream.fileno(), uid, gid)
            stream.write(body)
            stream.flush()
            os.fsync(stream.fileno())
        os.link(name, path)  # Never overwrite an existing file.
    finally:
        Path(name).unlink(missing_ok=True)
    return True


def compose_config(private_ip):
    return {'services': {
        'mysql-exporter': {
            'image': IMAGES['mysql-exporter'], 'user': '65534:65534',
            'restart': 'unless-stopped',
            'command': ['--config.my-cnf=/etc/mysqld-exporter/.my.cnf',
                        '--web.listen-address=:9104'],
            'ports': [private_ip + ':9104:9104'],
            'volumes': ['/etc/zipsai/mysql-exporter.cnf:/etc/mysqld-exporter/.my.cnf:ro'],
            'networks': ['service-tier']},
        'node-exporter': {
            'image': IMAGES['node-exporter'], 'user': '65534:65534',
            'restart': 'unless-stopped', 'network_mode': 'host', 'pid': 'host',
            'command': ['--path.rootfs=/host', '--web.listen-address=' + private_ip + ':9100',
                        '--collector.filesystem.mount-points-exclude=^/(dev|proc|sys|var/lib/docker/.+|var/lib/containers/storage/.+)($|/)'],
            'volumes': ['/:/host:ro,rslave']}},
        'networks': {'service-tier': {'external': True, 'name': NETWORK}}}


def existing_exporters(private_ip):
    found = {}
    for service in IMAGES:
        candidates = [c for c in [inspect('zipsai-' + service + '-1'),
                                  inspect('zipsai-monitoring-' + service + '-1')] if c]
        if len(candidates) > 1:
            raise SafeError('duplicate_exporters')
        if not candidates:
            continue
        container = candidates[0]
        if (container['Config']['Image'] != IMAGES[service]
                or not container['State']['Running']
                or container['HostConfig']['RestartPolicy']['Name'] != 'unless-stopped'):
            raise SafeError('existing_exporter_mismatch')
        args = container['Config'].get('Cmd') or []
        if service == 'mysql-exporter':
            bindings = container['HostConfig']['PortBindings'].get('9104/tcp')
            mounts = container['Mounts']
            config_mounts = [m for m in mounts if m['Source'] == str(CONFIG)
                             and m['Destination'] == '/etc/mysqld-exporter/.my.cnf'
                             and not m['RW']]
            valid = (bindings == [{'HostIp': private_ip, 'HostPort': '9104'}]
                     and NETWORK in container['NetworkSettings']['Networks']
                     and len(config_mounts) == 1
                     and '--config.my-cnf=/etc/mysqld-exporter/.my.cnf' in args)
        else:
            valid = (container['HostConfig']['NetworkMode'] == 'host'
                     and '--web.listen-address=' + private_ip + ':9100' in args
                     and '--path.rootfs=/host' in args
                     and any(m['Source'] == '/' and m['Destination'] == '/host'
                             and not m['RW'] for m in container['Mounts']))
        if not valid:
            raise SafeError('existing_exporter_configuration_mismatch')
        found[service] = container['Id']
    return found


def ensure_exporters(private_ip, found):
    body = json.dumps(compose_config(private_ip), indent=2) + '\n'
    exclusive_file(COMPOSE, body, 0o644)
    base = ['docker', 'compose', '-p', 'zipsai-monitoring', '-f', str(COMPOSE)]
    common.command([*base, 'config', '--quiet'])
    missing = sorted(set(IMAGES) - set(found))
    if missing:
        common.command([*base, 'pull', *missing])
        common.command([*base, 'up', '-d', '--no-deps', '--no-build',
                        '--no-recreate', '--pull', 'never', *missing])
    return missing


def main():
    if os.geteuid() != 0:
        raise SafeError('root_required')
    target = os.environ.get('SSM_ExpectedInstanceId', '')
    parameter = os.environ.get('SSM_PasswordParameter', '')
    private_ip = os.environ.get('SSM_PrivateIp', '')
    if not re.fullmatch(r'i-[0-9a-f]{17}', target):
        raise SafeError('instance_id_required')
    if parameter not in ['/zipsai/staging/mysql/exporter-password',
                          '/zipsai/prod/mysql-v1/exporter-password']:
        raise SafeError('parameter_not_allowed')
    if not ipaddress.IPv4Address(private_ip).is_private:
        raise SafeError('private_ip_required')
    lock = open('/run/zipsai-v1-exporters.lock', 'w')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    password = common.identity_and_secret(parameter, target)
    container = inspect(MYSQL)
    if (not container or not container['State']['Running']
            or container['State'].get('Health', {}).get('Status') != 'healthy'
            or NETWORK not in container['NetworkSettings']['Networks']):
        raise SafeError('mysql_not_ready')
    before = protected_state()
    found = existing_exporters(private_ip)
    check_config(password)  # Abort mismatch before DB mutations.
    if found.get('mysql-exporter') and not CONFIG.exists():
        raise SafeError('running_exporter_config_missing')
    created = ensure_account(password)
    config_created = False
    if not CONFIG.exists():
        body = common.render_config(password).replace('host=127.0.0.1', 'host=mysql')
        config_created = exclusive_file(CONFIG, body, 0o600, 65534, 65534)
    started = ensure_exporters(private_ip, found)
    if before != protected_state():
        raise SafeError('protected_container_state_changed')
    after = existing_exporters(private_ip)
    if any(after.get(service) != identifier for service, identifier in found.items()):
        raise SafeError('existing_exporter_recreated')
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    for _ in range(10):
        try:
            body = opener.open('http://' + private_ip + ':9104/metrics', timeout=5).read().decode()
            node = opener.open('http://' + private_ip + ':9100/metrics', timeout=5).read().decode()
            if 'mysql_up 1' in body.splitlines() and 'node_exporter_build_info{' in node:
                print(json.dumps({'result': 'ok', 'account_created': created,
                                  'config_created': config_created, 'exporters_started': started,
                                  'existing_exporters_preserved': len(found),
                                  'protected_containers_unchanged': True, 'mysql_up': 1}))
                return
        except Exception:
            pass
        time.sleep(1)
    raise SafeError('exporter_health_failed')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(json.dumps({'result': 'failed', 'reason': str(error)
                          if isinstance(error, SafeError) else type(error).__name__}))
        raise SystemExit(1) from None
