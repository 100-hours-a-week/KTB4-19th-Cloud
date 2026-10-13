resource "aws_subnet" "public_2a" {
  vpc_id                  = aws_vpc.zipsai.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = true

  tags = merge(var.shared_tags, {
    Name = "zipsai-shared-public-subnet-2a"
  })
}

resource "aws_subnet" "private_app_2c" {
  vpc_id                  = aws_vpc.zipsai.id
  cidr_block              = "10.0.10.0/24"
  availability_zone       = "ap-northeast-2c"
  map_public_ip_on_launch = false

  tags = merge(var.shared_tags, {
    Name = "zipsai-shared-private-app-subnet-2c"
  })
}

resource "aws_subnet" "private_data_2c" {
  vpc_id                  = aws_vpc.zipsai.id
  cidr_block              = "10.0.20.0/24"
  availability_zone       = "ap-northeast-2c"
  map_public_ip_on_launch = false

  tags = merge(var.shared_tags, {
    Name = "zipsai-shared-private-data-subnet-2c"
  })
}

resource "aws_subnet" "private_data_2a" {
  vpc_id                  = aws_vpc.zipsai.id
  cidr_block              = "10.0.21.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = false

  tags = merge(var.shared_tags, {
    Name = "zipsai-shared-private-data-subnet-2a"
  })
}
