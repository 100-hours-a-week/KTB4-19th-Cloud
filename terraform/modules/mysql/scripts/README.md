# V2 MySQL Exporter configuration

## Scope

Packer installs native node_exporter/mysqld_exporter binaries, OS users and systemd
units. This module's opt-in SSM document fills the remaining account/configuration
gap without replacing the EC2 host. V1 Docker hosts are deliberately excluded.

- Default: disabled. Staging and prod explicitly enable it with separate parameters.
- Terraform stores only the SecureString name, not the password.
- Each SSM Association targets one explicit instance ID and passes that ID to
  the script. IMDSv2 identity must match before the password is requested.
- Python standard-library SigV4 calls Parameter Store using the instance role;
  AWS CLI, pip, additional IAM policies and external downloads are unnecessary.

## Existing staging preservation

An existing account must authenticate using the Parameter value, be unlocked,
have MAX_USER_CONNECTIONS=3, and have exactly SELECT, PROCESS and REPLICATION
CLIENT globally. Unexpected credentials, privileges or file settings cause a
failure. The script never ALTERs an existing account or rotates its password.

An existing /etc/zipsai/mysql-exporter.cnf must have the expected account,
127.0.0.1 host, matching password and 0640 root:mysqld_exporter permissions.
It is not rewritten. Healthy enabled services are not restarted.

## New native V2 hosts

The script requires a root socket login and active MySQL/Packer-installed units.
It creates only mysqld_exporter@127.0.0.1 when absent. Creation refuses a
read_only/super_read_only node instead of changing those global settings.
Account DDL uses session sql_log_bin=0 so monitoring provisioning is local.

The password is read only into process memory, passed to mysql through the
child environment (never argv), and written into a restricted local config.
SQL errors/stdout containing potential secret material are not emitted.
The final check requires mysql_up=1 from the local exporter.

New config creation is exclusive; an existing file is never overwritten.
A failed initial account/configuration setup may leave its newly created
monitoring account or file for inspection. No automatic DROP USER rollback is
performed. The next run is idempotent when the completed settings match.

## Validation and rollback

Run the Python tests, terraform fmt/validate, and inspect a full environment
plan. For staging, the expected initial plan is one SSM document and two
associations only. Compare before/after grants, file metadata, service
start times and Prometheus node/MySQL targets. A second execution must report
account_created=false, config_created=false and services_started=[].

Disabling the flag removes the SSM management resources only; it does not remove
database accounts, config files or stop exporters. Rollback is therefore
non-destructive. Runtime restoration after an unexpected change requires a
separate reviewed operation; do not use DROP USER or restore a whole database.

V1 Compose support is excluded. Production uses a separate document and two
associations; inspect the full prod plan before applying it.
