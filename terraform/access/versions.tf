terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  backend "s3" {
    bucket       = "zipsai-v2-terraform-state"
    key          = "access/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region              = "ap-northeast-2"
  allowed_account_ids = ["929368845727"]
  # No default tags: importing the existing policy must not mutate its metadata.
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  region  = "ap-northeast-2"
  account = data.aws_caller_identity.current.account_id
  prefix  = "arn:${data.aws_partition.current.partition}"
}
