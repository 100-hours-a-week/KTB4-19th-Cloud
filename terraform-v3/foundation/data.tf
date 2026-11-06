data "aws_vpc" "shared" {
  tags = {
    Name = "zipsai-shared-vpc"
  }
}

data "aws_subnet" "shared" {
  for_each = {
    public_2a      = "zipsai-shared-public-subnet-2a"
    public_2c      = "zipsai-shared-public-subnet-2c"
    private_app_2c = "zipsai-shared-private-app-subnet-2c"
  }

  vpc_id = data.aws_vpc.shared.id
  tags = {
    Name = each.value
  }
}

data "aws_nat_gateway" "shared" {
  subnet_id = data.aws_subnet.shared["public_2c"].id
  state     = "available"
  tags = {
    Name = "zipsai-shared-nat-2c"
  }
}

data "aws_ecr_repository" "shared" {
  for_each = {
    backend   = "zipsai-backend"
    ai_api    = "zipsai-ai-api"
    embedding = "zipsai-embedding"
  }

  name = each.value
}

data "aws_s3_bucket" "uploads" {
  for_each = {
    prod    = "zipsai-prod-uploads"
    staging = "zipsai-staging-uploads"
  }

  bucket = each.value
}

data "aws_route53_zone" "private" {
  name         = "zipsai.internal."
  private_zone = true
  vpc_id       = data.aws_vpc.shared.id
}

