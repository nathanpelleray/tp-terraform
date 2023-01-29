### Module Main

provider "aws" {
  region = var.aws_region
}

resource "aws_vpc" "vpc" {
  cidr_block = var.cidr_block

  tags = {
    Name = "${var.vpc_name}-vpc"
  }
}

resource "aws_subnet" "public" {
  /* For each ne prend que un map ou set */
  for_each          = var.azs
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = cidrsubnet(var.cidr_block, 4, each.value)
  availability_zone = "${var.aws_region}${each.key}"

  /* Assign public ip */
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.vpc_name}-public-${var.aws_region}${each.key}"
  }
}

resource "aws_subnet" "private" {
  for_each          = var.azs
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = cidrsubnet(var.cidr_block, 4, 15 - each.value)
  availability_zone = "${var.aws_region}${each.key}"

  tags = {
    Name = "${var.vpc_name}-private-${var.aws_region}${each.key}"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.vpc_name}-igw"
  }
}

/* Nat ami*/
data "aws_ami" "ami_nat" {
  most_recent = true
  name_regex  = "^amzn-ami-vpc-nat-2018.03.0.2021*"
  owners      = ["amazon"]
}

resource "aws_security_group" "security_group" {
  name        = "security group"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.vpc.id

  tags = {
    Name = "allow_tls"
  }
}

resource "aws_security_group_rule" "rule_ingress_nat" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.security_group.id
}

resource "aws_security_group_rule" "rule_ingress_ec2" {
  type              = "ingress"
  from_port         = -1
  to_port           = -1
  protocol          = -1
  cidr_blocks       = [aws_vpc.vpc.cidr_block]
  security_group_id = aws_security_group.security_group.id
}

resource "aws_security_group_rule" "rule_egress_nat" {
  type              = "egress"
  from_port         = -1
  to_port           = -1
  protocol          = -1
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.security_group.id
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDgN9qyo8YlMoVw02zAutXJAbm362m+BDypk20vTZB9CxstISO9jKT9I6Ab9949ZYRt9ho5iUzLsE4nVprNM2GlHQUzxSUQsHoXPMyt0Tzi2e748cPZr5xucRy24E1+ja92WBCnyuMX4L8/mwqJDoDFNYCFEcNP5wx5IEjr/wUkrUAzDnedQjjHfaUbMD/UdzFHsLtZ/ijZpQezvxfGxHGJA9Cb7i36v8HWl6TDQ5DHWkFLovWwiuFxVGv51IXgR9aZmh9wCpbm3ntmrVfWihL8Uco7TLlW6TOWiGqZAhwjqUtHhsCoJLQcTVNXU6NDp6HMBz4pGvX6cqafpa2A2pZq8pbxwPTqsLnHp6o1N36QL5TatZRYaSspqbB9gzSkrUyspQIxnBqvfk6y2i9Dac3dcWTk4ta2gxHZPdR/mGFhDLHk7+quGJci5OSaNjxFhej8ochi7lZ50UvA0zYmJn0NGueqNg6nNfUYmbKwB2E3UKUL9MLIYlGFCbINNw7PJQE= nathan@pc-nathan"
}

resource "aws_instance" "nat_instance" {
  for_each               = var.azs
  ami                    = data.aws_ami.ami_nat.id
  instance_type          = "t2.micro"
  source_dest_check      = false
  vpc_security_group_ids = [aws_security_group.security_group.id]
  subnet_id              = aws_subnet.public[each.key].id
  key_name               = aws_key_pair.deployer.key_name

  tags = {
    Name = "${var.vpc_name}-nat-${var.aws_region}${each.key}"
  }
}

/** EIP pour les nat (réservation d'une IP public) **/
resource "aws_eip" "eip_nat" {
  for_each = var.azs
  vpc      = true
}

/** Association des IPs au instance **/
resource "aws_eip_association" "eip_association_nat" {
  for_each      = var.azs
  instance_id   = aws_instance.nat_instance[each.key].id
  allocation_id = aws_eip.eip_nat[each.key].id
}

/** Table de routage **/
resource "aws_route_table" "private_route_table" {
  for_each = var.azs
  vpc_id   = aws_vpc.vpc.id

  tags = {
    Name = "${var.vpc_name}-private-${var.aws_region}${each.key}"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.vpc_name}-public"
  }
}

/** Routes **/
resource "aws_route" "private_route" {
  for_each               = var.azs
  route_table_id         = aws_route_table.private_route_table[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat_instance[each.key].primary_network_interface_id
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

/** Association des routes et des subnets **/
resource "aws_route_table_association" "private_associate" {
  for_each       = var.azs
  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private_route_table[each.key].id
}

resource "aws_route_table_association" "public_associate" {
  for_each       = var.azs
  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public_route_table.id
}
