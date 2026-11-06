resource "aws_subnet" "v3_private_app_2a" {
  vpc_id                  = data.aws_vpc.shared.id
  cidr_block              = "10.0.11.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = false

  tags = merge(local.v3_tags, {
    Name = "zipsai-v3-private-app-subnet-2a"
  })
}

resource "aws_route_table" "v3_private_app_2a" {
  vpc_id = data.aws_vpc.shared.id

  tags = merge(local.v3_tags, {
    Name = "zipsai-v3-private-app-rt-2a"
  })
}

resource "aws_route" "v3_private_app_2a_ipv4_default" {
  route_table_id         = aws_route_table.v3_private_app_2a.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = data.aws_nat_gateway.shared.id
}

resource "aws_route_table_association" "v3_private_app_2a" {
  subnet_id      = aws_subnet.v3_private_app_2a.id
  route_table_id = aws_route_table.v3_private_app_2a.id
}
