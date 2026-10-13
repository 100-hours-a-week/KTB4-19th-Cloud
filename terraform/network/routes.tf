resource "aws_eip" "nat_2c" {
  domain = "vpc"

  tags = merge(var.shared_tags, {
    Name = "zipsai-shared-nat-eip-2c"
  })
}

resource "aws_nat_gateway" "app_2c" {
  allocation_id = aws_eip.nat_2c.id
  subnet_id     = aws_subnet.public_2c.id

  tags = merge(var.shared_tags, {
    Name = "zipsai-shared-nat-2c"
  })

  depends_on = [aws_internet_gateway.zipsai]
}

resource "aws_route_table_association" "public_2a" {
  subnet_id      = aws_subnet.public_2a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.zipsai.id

  tags = merge(var.shared_tags, {
    Name = "zipsai-shared-private-app-rt"
  })
}

resource "aws_route" "private_app_ipv4_default" {
  route_table_id         = aws_route_table.private_app.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.app_2c.id
}

resource "aws_route_table_association" "private_app_2c" {
  subnet_id      = aws_subnet.private_app_2c.id
  route_table_id = aws_route_table.private_app.id
}

resource "aws_route_table" "private_data" {
  vpc_id = aws_vpc.zipsai.id

  tags = merge(var.shared_tags, {
    Name = "zipsai-shared-private-data-rt"
  })
}

resource "aws_route_table_association" "private_data_2c" {
  subnet_id      = aws_subnet.private_data_2c.id
  route_table_id = aws_route_table.private_data.id
}

resource "aws_route_table_association" "private_data_2a" {
  subnet_id      = aws_subnet.private_data_2a.id
  route_table_id = aws_route_table.private_data.id
}
