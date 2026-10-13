# Network

V2가 재사용하는 기존 VPC 기반과 이후 추가할 Public·Private Network 자원을 관리한다.

## 최초 Import 범위

- `zipsai-prod-vpc`
- 기존 `ap-northeast-2c` Public Subnet
- Internet Gateway
- Main·Public Route Table
- Public Route Table의 기본 인터넷 Route와 기존 Subnet 연결

`imports.tf`는 기존 AWS 자원과 Terraform Resource 주소를 최초로 연결한다. Import가 완료된 뒤에는 S3의 `network/terraform.tfstate`가 연결 정보를 보관한다.

## 신규 확장 범위

- `ap-northeast-2a` Public Subnet
- `ap-northeast-2c` Private App Subnet
- `ap-northeast-2a`·`2c` Private Data Subnet
- Private App Subnet의 단일 NAT Gateway 경로
- 인터넷 기본 Route가 없는 Private Data Route Table
- App·Data Route Table에 연결하는 S3 Gateway Endpoint
- Private Data Subnet의 MySQL EC2가 Session Manager를 사용할 수 있도록 `ap-northeast-2c`에 SSM Interface Endpoint 2종(`ssm`, `ssmmessages`)

SSM Endpoint는 비용을 줄이기 위해 2c에만 배치하지만, Endpoint Security Group은 2a·2c Data Subnet의 HTTPS 접근을 모두 허용한다. 따라서 두 AZ의 MySQL EC2를 모두 Session Manager로 관리할 수 있다. 단, 2c AZ 장애 시 SSM 관리 경로는 일시적으로 사용할 수 없다.

## 실행 순서

```bash
export AWS_PROFILE=terraform
terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan
```

Import Plan에 기존 자원의 변경이나 삭제가 없어야 한다. 승인된 Plan만 적용하고, 적용 후 다시 Plan을 실행해 변경 없음 상태를 확인한다.
