terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Import 단계에서는 기존 태그를 그대로 보존한다.
provider "aws" {
  region              = "ap-northeast-2"
  allowed_account_ids = ["929368845727"]
}
