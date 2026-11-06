terraform {
  backend "s3" {
    bucket       = "zipsai-v3-terraform-state"
    key          = "foundation/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
