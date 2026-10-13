resource "aws_vpc" "zipsai" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  instance_tenancy     = "default"

  tags = merge(var.shared_tags, {
    Name = "zipsai-shared-vpc"
  })
}

resource "aws_subnet" "public_2c" {
  vpc_id                  = aws_vpc.zipsai.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-2c"
  map_public_ip_on_launch = true

  tags = merge(var.shared_tags, {
    Name = "zipsai-shared-public-subnet-2c"
  })
}

resource "aws_internet_gateway" "zipsai" {
  vpc_id = aws_vpc.zipsai.id

  tags = merge(var.shared_tags, {
    Name = "zipsai-shared-igw"
  })
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.zipsai.id

  tags = merge(var.shared_tags, {
    Name = "zipsai-shared-main-rt"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.zipsai.id

  tags = merge(var.shared_tags, {
    Name = "zipsai-shared-public-rt"
  })
}

resource "aws_route" "public_ipv4_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.zipsai.id
}

resource "aws_route_table_association" "public_2c" {
  subnet_id      = aws_subnet.public_2c.id
  route_table_id = aws_route_table.public.id
}
