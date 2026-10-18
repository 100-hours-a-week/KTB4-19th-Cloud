#!/usr/bin/env python3
"""Provision migration accounts only; never rotate existing credentials or change GTID."""
import fcntl
import ipaddress
import json
import os
import re
import subprocess
from pathlib import Path

import configure_mysql_exporter as common

SafeError = common.SafeError
APP_PRIVILEGES = {'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'CREATE', 'DROP', 'ALTER', 'INDEX', 'REFERENCES'}
REPL_PRIVILEGES = {'REPLICATION SLAVE', 'REPLICATION CLIENT'}


def validate_plan(plan):
    if plan.get('schema_version') != 1 or plan.get('engine') not in ('docker', 'native'):
        raise SafeError('invalid_plan')
    if not re.fullmatch(r'i-[0-9a-f]+', plan.get('instance_id', '')):
        raise SafeError('invalid_instance')
    if plan.get('server_id') not in (1, 101, 102):
        raise SafeError('invalid_server_id')
    if not plan.get('accounts'):
        raise SafeError('empty_accounts')
    for account in plan['accounts']:
        if account.get('kind') not in ('app', 'replication'):
            raise SafeError('invalid_account_kind')
        if account.get('user') != ('zipsai_app' if account['kind'] == 'app' else 'zipsai_repl'):
            raise SafeError('invalid_account_name')
        if account['kind'] == 'app':
            if plan['engine'] != 'native' or account.get('host') != '%':
                raise SafeError('app_account_wrong_scope')
        else:
            try:
                ipaddress.IPv4Address(account['host'])
            except (KeyError, ValueError):
                raise SafeError('invalid_replication_host')
        expected = '/zipsai/prod/mysql-v1/replication-password' if plan['engine'] == 'docker' else (
            '/zipsai/prod/mysql-v2/password' if account['kind'] == 'app' else '/zipsai/prod/mysql-v2/replication-password')
        if account.get('parameter') != expected:
            raise SafeError('unexpected_secret_path')
    return plan


def mysql(plan, sql, password=None, user='root', host=None):
    env = os.environ.copy()
    env.pop('MYSQL_PWD', None)
    args = ['mysql', '--no-defaults', '--batch', '--skip-column-names', '--connect-timeout=5', '--user=' + user]
    if plan['engine'] == 'docker':
        if user != 'root' or host:
            raise SafeError('docker_non_root_login_not_supported')
        result = common.command(['docker', 'inspect', 'zipsai-mysql-1'])
        item = json.loads(result.stdout)[0]
        values = dict(x.split('=', 1) for x in item['Config']['Env'] if '=' in x)
        password = values.get('MYSQL_ROOT_PASSWORD')
        if not password:
            raise SafeError('root_credential_unavailable')
        args = ['docker', 'exec', '-i', '-e', 'MYSQL_PWD', 'zipsai-mysql-1'] + args + ['--protocol=socket']
    else:
        args += ['--protocol=tcp', '--host=' + host] if host else ['--protocol=socket']
    if password is not None:
        env['MYSQL_PWD'] = password
    return common.command(args, sql=sql, env=env).stdout.strip()


def expected_grant(account):
    return (APP_PRIVILEGES, '`zipsai`.*') if account['kind'] == 'app' else (REPL_PRIVILEGES, '*.*')


def verify_grants(plan, account):
    identity = common.sql_literal(account['user']) + '@' + common.sql_literal(account['host'])
    metadata = mysql(plan, 'SELECT account_locked FROM mysql.user WHERE user=' + common.sql_literal(account['user']) + ' AND host=' + common.sql_literal(account['host']) + ';')
    if metadata != 'N':
        raise SafeError('account_locked_or_missing')
    grants = mysql(plan, 'SHOW GRANTS FOR ' + identity + ';').splitlines()
    privileges, scope = expected_grant(account)
    effective = [g for g in grants if not g.startswith('GRANT USAGE ON *.* TO ')]
    match = re.fullmatch(r'GRANT (.+) ON ' + re.escape(scope) + r' TO .+', effective[0]) if len(effective) == 1 else None
    if not match or set(match[1].split(', ')) != privileges or any('WITH GRANT OPTION' in g for g in grants):
        raise SafeError('existing_grants_mismatch_review_required')


def existing_account(plan, account):
    return mysql(plan, 'SELECT COUNT(*) FROM mysql.user WHERE user=' + common.sql_literal(account['user']) + ' AND host=' + common.sql_literal(account['host']) + ';') == '1'


def ensure_account(plan, account, password):
    if existing_account(plan, account):
        verify_grants(plan, account)
        return False
    if mysql(plan, 'SELECT @@GLOBAL.read_only,@@GLOBAL.super_read_only;') != '0\t0':
        raise SafeError('readonly_node_no_account_created')
    privileges, scope = expected_grant(account)
    identity = common.sql_literal(account['user']) + '@' + common.sql_literal(account['host'])
    # Provision locally on each node. Account DDL must not enter future replication.
    mysql(plan, "SET SESSION sql_log_bin=0; SET SESSION sql_mode='NO_BACKSLASH_ESCAPES'; CREATE USER " + identity + ' IDENTIFIED BY ' + common.sql_literal(password) + '; GRANT ' + ','.join(sorted(privileges)) + ' ON ' + scope + ' TO ' + identity + ';')
    verify_grants(plan, account)
    return True


def protected_state(plan):
    variables = mysql(plan, 'SELECT @@GLOBAL.gtid_mode,@@GLOBAL.enforce_gtid_consistency,@@GLOBAL.read_only,@@GLOBAL.super_read_only,@@GLOBAL.auto_increment_increment,@@GLOBAL.auto_increment_offset;')
    if plan['engine'] == 'docker':
        ids = common.command(['docker', 'ps', '-aq']).stdout.split()
        containers = json.loads(common.command(['docker', 'inspect', *ids]).stdout) if ids else []
        runtime = sorted((c['Id'], c['State']['StartedAt'], c['State']['Running']) for c in containers)
    else:
        runtime = common.command(['systemctl', 'show', 'mysql', '--property=MainPID,ActiveEnterTimestampMonotonic']).stdout
    return variables, runtime


def main():
    plan = validate_plan(json.loads(os.environ['SSM_AccountPlan']))
    if os.geteuid() != 0:
        raise SafeError('root_required')
    with open('/run/lock/zipsai-migration-accounts.lock', 'a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        # Get every secret and verify instance identity before any database mutation.
        passwords = [common.identity_and_secret(a['parameter'], plan['instance_id']) for a in plan['accounts']]
        if mysql(plan, 'SELECT @@GLOBAL.server_id;') != str(plan['server_id']):
            raise SafeError('unexpected_mysql_server')
        before = protected_state(plan)
        for a in plan['accounts']:
            if existing_account(plan, a):
                verify_grants(plan, a)
        results = []
        for a, password in zip(plan['accounts'], passwords):
            created = ensure_account(plan, a, password)
            if a['kind'] == 'app':
                if mysql(plan, 'SELECT CURRENT_USER();', password, a['user'], '127.0.0.1') != 'zipsai_app@%':
                    raise SafeError('app_authentication_mismatch')
            results.append({'user':a['user'], 'host':a['host'], 'created':created, 'grants_verified':True})
        if protected_state(plan) != before:
            raise SafeError('protected_state_changed')
        print(json.dumps({'status':'success','instance':plan['instance_id'],'accounts':results,'gtid_and_runtime_unchanged':True}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # SQL/SDK errors may include credentials; never print their raw messages.
        message = str(error) if isinstance(error, SafeError) else type(error).__name__
        print(json.dumps({'status':'failed','reason':message}))
        raise SystemExit(1)
