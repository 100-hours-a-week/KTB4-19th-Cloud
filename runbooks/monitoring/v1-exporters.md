# V1 Migration Exporter 실행

V1 MySQL과 V2 MySQL을 같은 Prometheus에서 비교하기 위해 마이그레이션 기간에만 V1 Exporter를 실행한다. 기존 CloudWatch 수집은 그대로 유지한다.

## 1. MySQL 조회 전용 계정

V1 MySQL에서 Exporter 전용 계정을 생성한다. 실제 Password는 Parameter Store 등 안전한 위치에서 별도로 관리한다.

```sql
CREATE USER 'mysqld_exporter'@'%' IDENTIFIED BY '<PASSWORD>'
  WITH MAX_USER_CONNECTIONS 3;
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.*
  TO 'mysqld_exporter'@'%';
```

## 2. V1 EC2 설정 파일

V1 EC2의 `/etc/zipsai/mysql-exporter.cnf`를 다음 형식으로 만들고 저장소에는 Commit하지 않는다.

```ini
[client]
user=mysqld_exporter
password=<PASSWORD>
host=mysql
port=3306
protocol=tcp
```

파일은 Exporter Container만 읽을 수 있도록 권한을 제한한다.

## 3. Exporter 실행

```bash
docker compose --profile migration-monitoring up -d mysql-exporter node-exporter
```

Prometheus는 Private DNS `mysql-v1.prod.zipsai.internal`을 통해 `9100`, `9104`를 수집한다. 두 Port는 Monitoring Server Security Group에서만 접근할 수 있다.

마이그레이션 검증이 끝나면 다음 명령으로 임시 Exporter를 종료한다.

```bash
docker compose --profile migration-monitoring stop mysql-exporter node-exporter
```
