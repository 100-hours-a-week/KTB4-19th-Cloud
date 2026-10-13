# Terraform State Bootstrap

Terraform State를 저장할 S3 Bucket을 최초 1회 생성한다. Bucket에는 Versioning, SSE-S3 암호화, Public Access 차단, HTTPS 강제 정책과 삭제 방지를 적용한다.

## 최초 생성

State Bucket 자체가 아직 없으므로 최초 실행은 Local State를 사용한다.

```bash
export AWS_PROFILE=terraform
terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

`apply`는 Plan과 대상 AWS Account를 확인한 뒤에만 실행한다.

## Bootstrap State 이전

Bucket 생성 후 `backend.tf.example`과 같은 내용으로 `backend.tf`를 만들고 다음 명령으로 Local State를 S3로 이전한다.

```bash
terraform init -migrate-state
```

이후 Root Module은 서로 다른 `key`를 사용하고 `use_lockfile = true`를 설정한다.

| Root Module | State Key |
| --- | --- |
| Bootstrap | `bootstrap/terraform.tfstate` |
| Network | `network/terraform.tfstate` |
| Shared | `shared/terraform.tfstate` |
| Staging | `environments/staging/terraform.tfstate` |
| Production | `environments/prod/terraform.tfstate` |
