#!/usr/bin/env python3
"""Configure native V2 MySQL monitoring without rotating existing credentials."""
import configparser
import datetime
import fcntl
import grp
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile
import time
import urllib.request

CONFIG = Path("/etc/zipsai/mysql-exporter.cnf")
USER = "mysqld_exporter"
DB_HOST = "127.0.0.1"


class SafeError(Exception):
    pass


def command(args, *, sql=None, env=None, check=True):
    result = subprocess.run(args, input=sql, env=env, capture_output=True,
                            text=True, timeout=30)
    if check and result.returncode:
        # SQL errors can contain passwords. Never emit stdout/stderr on failure.
        raise SafeError("command_failed:" + args[0])
    return result


def mysql(sql, password=None):
    args = ["mysql", "--no-defaults", "--batch", "--skip-column-names",
            "--connect-timeout=5"]
    env = os.environ.copy()
    env.pop("MYSQL_PWD", None)
    if password is None:
        args += ["--protocol=socket", "--user=root"]
    else:
        args += ["--protocol=tcp", "--host=" + DB_HOST, "--user=" + USER]
        env["MYSQL_PWD"] = password
    return command(args, sql=sql, env=env).stdout.strip()


def sql_literal(value):
    # Only used after setting session sql_mode=NO_BACKSLASH_ESCAPES.
    return "'" + value.replace("'", "''") + "'"


def validate_password(value):
    if not value or any(c in value for c in "\x00\r\n"):
        raise SafeError("unsupported_password_format")
    return value


def render_config(password):
    value = validate_password(password).replace("\\", "\\\\").replace('"', '\\"')
    return '[client]\nuser=mysqld_exporter\npassword="' + value + '"\nhost=127.0.0.1\n'


def config_password(text):
    parser = configparser.RawConfigParser()
    parser.read_string(text)
    if parser.get("client", "user") != USER or parser.get("client", "host") != DB_HOST:
        raise SafeError("existing_config_identity_mismatch")
    value = parser.get("client", "password")
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        value = value[1:-1]
        escapes = {"b": "\b", "t": "\t", "n": "\n", "r": "\r", "s": " ",
                   "\\": "\\", "'": "'", '"': '"'}
        value = re.sub(r"\\(.)", lambda m: escapes.get(m[1], m[0]), value)
    return value


def identity_and_secret(parameter, expected_id):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    token_request = urllib.request.Request(
        "http://169.254.169.254/latest/api/token", method="PUT",
        headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"})
    token = opener.open(token_request, timeout=5).read().decode()

    def metadata(path):
        request = urllib.request.Request("http://169.254.169.254/latest/" + path,
            headers={"X-aws-ec2-metadata-token": token})
        return opener.open(request, timeout=5).read().decode()

    identity = json.loads(metadata("dynamic/instance-identity/document"))
    if identity["instanceId"] != expected_id:
        raise SafeError("unexpected_instance")
    role = metadata("meta-data/iam/security-credentials/").strip()
    credentials = json.loads(metadata("meta-data/iam/security-credentials/" + role))
    region = identity["region"]
    host = "ssm." + region + ".amazonaws.com"
    body = json.dumps({"Name": parameter, "WithDecryption": True},
                      separators=(",", ":")).encode()
    now = datetime.datetime.now(datetime.timezone.utc)
    date, stamp = now.strftime("%Y%m%d"), now.strftime("%Y%m%dT%H%M%SZ")
    headers = {"content-type": "application/x-amz-json-1.1", "host": host,
               "x-amz-date": stamp, "x-amz-security-token": credentials["Token"],
               "x-amz-target": "AmazonSSM.GetParameter"}
    signed = ";".join(sorted(headers))
    canonical_headers = "".join(k + ":" + headers[k] + "\n" for k in sorted(headers))
    canonical = "POST\n/\n\n" + canonical_headers + "\n" + signed + "\n" + hashlib.sha256(body).hexdigest()
    scope = date + "/" + region + "/ssm/aws4_request"
    to_sign = "AWS4-HMAC-SHA256\n" + stamp + "\n" + scope + "\n" + hashlib.sha256(canonical.encode()).hexdigest()

    def digest(key, value):
        return hmac.new(key, value.encode(), hashlib.sha256).digest()

    key = digest(digest(digest(digest(("AWS4" + credentials["SecretAccessKey"]).encode(),
                                     date), region), "ssm"), "aws4_request")
    signature = hmac.new(key, to_sign.encode(), hashlib.sha256).hexdigest()
    headers["Authorization"] = ("AWS4-HMAC-SHA256 Credential=" + credentials["AccessKeyId"]
        + "/" + scope + ", SignedHeaders=" + signed + ", Signature=" + signature)
    request = urllib.request.Request("https://" + host + "/", data=body,
                                     headers=headers, method="POST")
    result = json.loads(opener.open(request, timeout=15).read())["Parameter"]
    if result["Name"] != parameter or result["Type"] != "SecureString":
        raise SafeError("unexpected_parameter")
    return validate_password(result["Value"])


def verify_account(password):
    mysql("SELECT 1;", password)
    metadata = mysql("SELECT account_locked,max_user_connections FROM mysql.user "
                     "WHERE user='mysqld_exporter' AND host='127.0.0.1';")
    if metadata != "N\t3":
        raise SafeError("existing_account_limits_mismatch")
    grants = mysql("SHOW GRANTS FOR CURRENT_USER;", password).splitlines()
    expected = {"SELECT", "PROCESS", "REPLICATION CLIENT"}
    global_grants = [line for line in grants if " ON *.* TO " in line and not line.startswith("GRANT USAGE ")]
    if len(global_grants) != 1:
        raise SafeError("existing_account_grants_mismatch")
    match = re.fullmatch(r"GRANT (.+) ON \*\.\* TO .+", global_grants[0])
    if not match or set(match[1].split(", ")) != expected or "WITH GRANT OPTION" in global_grants[0]:
        raise SafeError("existing_account_grants_mismatch")
    if len(grants) != len(global_grants):
        raise SafeError("unexpected_additional_grants")


def ensure_account(password):
    found = mysql("SELECT COUNT(*) FROM mysql.user WHERE user='mysqld_exporter' "
                  "AND host='127.0.0.1';")
    if found == "1":
        verify_account(password)  # Mismatch aborts; no ALTER/rotation/revocation.
        return False
    if found != "0":
        raise SafeError("unexpected_account_count")
    writable = mysql("SELECT @@GLOBAL.read_only,@@GLOBAL.super_read_only;")
    if writable != "0\t0":
        raise SafeError("account_missing_on_readonly_node")
    mysql("SET SESSION sql_log_bin=0; SET SESSION sql_mode='NO_BACKSLASH_ESCAPES'; "
          "CREATE USER 'mysqld_exporter'@'127.0.0.1' IDENTIFIED BY "
          + sql_literal(password) + " WITH MAX_USER_CONNECTIONS 3; "
          "GRANT SELECT,PROCESS,REPLICATION CLIENT ON *.* "
          "TO 'mysqld_exporter'@'127.0.0.1';")
    verify_account(password)
    return True


def ensure_config(password):
    gid = grp.getgrnam(USER).gr_gid
    if CONFIG.is_symlink():
        raise SafeError("config_symlink_rejected")
    if CONFIG.exists():
        if config_password(CONFIG.read_text()) != password:
            raise SafeError("existing_config_password_mismatch")
        metadata = CONFIG.stat()
        if stat.S_IMODE(metadata.st_mode) != 0o640 or metadata.st_uid != 0 or metadata.st_gid != gid:
            raise SafeError("existing_config_permissions_mismatch")
        return False  # Byte-for-byte preservation of existing config.
    CONFIG.parent.mkdir(mode=0o750, parents=True, exist_ok=True)
    temporary = None
    try:
        fd, temporary = tempfile.mkstemp(prefix=".mysql-exporter-", dir=CONFIG.parent)
        with os.fdopen(fd, "w") as stream:
            os.fchmod(stream.fileno(), 0o640)
            os.fchown(stream.fileno(), 0, gid)
            stream.write(render_config(password))
            stream.flush()
            os.fsync(stream.fileno())
        # Exclusive install: never overwrite an existing config.
        os.link(temporary, CONFIG)
    finally:
        if temporary is not None:
            Path(temporary).unlink(missing_ok=True)
    return True


def main():
    if os.geteuid() != 0:
        raise SafeError("root_required")
    parameter = os.environ.get("SSM_PasswordParameter", "")
    expected_id = os.environ.get("SSM_ExpectedInstanceId", "")
    if not re.fullmatch(r"/zipsai/(staging/mysql|prod/mysql-v2)/exporter-password", parameter):
        raise SafeError("parameter_not_allowed")
    if not re.fullmatch(r"i-[0-9a-f]{17}", expected_id):
        raise SafeError("instance_id_required")
    lock = open("/run/zipsai-mysql-exporter.lock", "w")
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    # Validate installed Packer artifacts before changing DB state.
    for unit in ("mysql", "node_exporter", "mysqld_exporter"):
        loaded = command(["systemctl", "show", unit, "--property=LoadState", "--value"]).stdout.strip()
        if loaded != "loaded":
            raise SafeError("missing_unit:" + unit)
    if command(["systemctl", "is-active", "--quiet", "mysql"], check=False).returncode:
        raise SafeError("mysql_not_active")
    grp.getgrnam(USER)
    password = identity_and_secret(parameter, expected_id)
    # Detect a conflicting file before any account creation.
    if CONFIG.exists():
        if CONFIG.is_symlink() or config_password(CONFIG.read_text()) != password:
            raise SafeError("existing_config_mismatch")
    account_created = ensure_account(password)
    config_created = ensure_config(password)
    started = []
    for unit in ("node_exporter", "mysqld_exporter"):
        if command(["systemctl", "is-enabled", "--quiet", unit], check=False).returncode:
            command(["systemctl", "enable", unit])
        if command(["systemctl", "is-active", "--quiet", unit], check=False).returncode:
            command(["systemctl", "start", unit])
            started.append(unit)
    for _ in range(10):
        try:
            body = urllib.request.urlopen("http://127.0.0.1:9104/metrics", timeout=5).read().decode()
            if "mysql_up 1" in body.splitlines():
                print(json.dumps({"result": "ok", "account_created": account_created,
                                  "config_created": config_created, "services_started": started,
                                  "mysql_up": 1}))
                return
        except Exception:
            pass
        time.sleep(1)
    raise SafeError("exporter_health_failed")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        message = str(error) if isinstance(error, SafeError) else type(error).__name__
        print(json.dumps({"result": "failed", "reason": message}))
        raise SystemExit(1) from None
