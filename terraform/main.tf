provider "aws" {
  region = "us-east-1"
}

# Create a secure VPC
resource "aws_vpc" "shield-vpc" {
  cidr_block = "10.0.0.0/16" 
  tags = {
    Name = "shield-vpc"
  }
}

# Create 2 Public Subnets across 2 Availability Zones
resource "aws_subnet" "public-subnet-1" {
  vpc_id            = aws_vpc.shield-vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-1"
  }
}

resource "aws_subnet" "public-subnet-2" {
  vpc_id            = aws_vpc.shield-vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-2"
  }
}

# Create 2 Private Subnets across 2 Availability Zones
resource "aws_subnet" "private-subnet-1" {
  vpc_id            = aws_vpc.shield-vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "private-subnet-1"
  }
}

resource "aws_subnet" "private-subnet-2" {
  vpc_id            = aws_vpc.shield-vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name = "private-subnet-2"
  }
}

# Attach an Internet Gateway to the VPC
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.shield-vpc.id
  tags = {
    Name = "shield-igw"
  }
}

# Create NAT Gateway in Public Subnet 1
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id    = aws_subnet.public-subnet-1.id
  tags = {
    Name = "shield-nat-gw"
  }
}

# Create Route Table for Public Subnets
resource "aws_route_table" "public-route" {
  vpc_id = aws_vpc.shield-vpc.id
  tags = {
    Name = "public-route"
  }
}
resource "aws_route" "public-route-to-igw" {
  route_table_id         = aws_route_table.public-route.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# Create route table for private subnets
resource "aws_route_table" "private-route" {
  vpc_id = aws_vpc.shield-vpc.id
  tags = {
    Name = "private-route"
  }
}
resource "aws_route" "private-route-to-nat" {
  route_table_id         = aws_route_table.private-route.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gw.id
}

# Create route table and subnet associations
resource "aws_route_table_association" "public-subnet-1-assoc" {
  subnet_id      = aws_subnet.public-subnet-1.id
  route_table_id = aws_route_table.public-route.id
}

resource "aws_route_table_association" "public-subnet-2-assoc" {
  subnet_id      = aws_subnet.public-subnet-2.id
  route_table_id = aws_route_table.public-route.id
}

resource "aws_route_table_association" "private-subnet-1-assoc" {
  subnet_id      = aws_subnet.private-subnet-1.id
  route_table_id = aws_route_table.private-route.id
}

resource "aws_route_table_association" "private-subnet-2-assoc" {
  subnet_id      = aws_subnet.private-subnet-2.id
  route_table_id = aws_route_table.private-route.id
}