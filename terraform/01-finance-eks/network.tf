locals {
  name = "${var.project_name}-${var.environment}"
  az_count = length(var.availability_zones)
}

# VPC
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = { Name = "${local.name}-vpc" }
}

# IGW
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "${local.name}-igw" }
}

# Public Subnet: ALB + EKS가 ELB를 만들 위치 태그 부여
resource "aws_subnet" "public" {
  count = local.az_count
  vpc_id = aws_vpc.main.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "${local.name}-public-${count.index + 1}"
    "kubernetes.io/role/elb" = "1"
  }
}

# Private Subnet: EKS Node Groupo + Internal ELB
resource "aws_subnet" "app" {
  count = local.az_count
  vpc_id = aws_vpc.main.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name= "${local.name}-app-${count.index + 1}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# DB Subnet: RDS
resource "aws_subnet" "data" {
  count = local.az_count
  vpc_id = aws_vpc.main.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index + 20)
  availability_zone = var.availability_zones[count.index]
  tags = { Name = "${local.name}-data-${count.index + 1}" }
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags = { Name = "${local.name}-nat-eip" }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id = aws_subnet.public[0].id
  tags= { Name = "${local.name}-nat" }Dynamo
  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${local.name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count = local.az_count
  subnet_id = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  tags = { Name = "${local.name}-private-rt" }
}

resource "aws_route_table_association" "app" {
  count = local.az_count
  subnet_id = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "data" {
  count = local.az_count
  subnet_id = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.private.id
}
