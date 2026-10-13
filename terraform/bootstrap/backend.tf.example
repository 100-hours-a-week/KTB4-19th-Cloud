terraform {
  backend "s3" {
    bucket       = "zipsai-v2-terraform-state"
    key          = "bootstrap/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
