import {
  to = aws_vpc.zipsai
  id = "vpc-0e01c25a55f10f584"
}

import {
  to = aws_subnet.public_2c
  id = "subnet-03a9a4e9df8e05d6b"
}

import {
  to = aws_internet_gateway.zipsai
  id = "igw-07cbbd8a9c7a5a5e7"
}

import {
  to = aws_route_table.main
  id = "rtb-043c4988bc33fc1e0"
}

import {
  to = aws_route_table.public
  id = "rtb-049a5f223d4471aad"
}

import {
  to = aws_route.public_ipv4_default
  id = "rtb-049a5f223d4471aad_0.0.0.0/0"
}

import {
  to = aws_route_table_association.public_2c
  id = "subnet-03a9a4e9df8e05d6b/rtb-049a5f223d4471aad"
}
