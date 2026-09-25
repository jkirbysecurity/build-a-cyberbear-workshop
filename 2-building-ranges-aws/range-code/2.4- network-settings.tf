##########################################################################################
# VARIABLES
##########################################################################################
# Set the default CIDR block you want to work in 
variable "cidr" {
  description = "The base CIDR block used for the VPC and all subnets" # Documents purpose
  default     = "10.0.0.0/16" # Sets default value
  type        = string # Data type
  validation { # Validation conditions and error message if validation fails
    condition     = contains(["16", "21"], split("/", var.cidr)[1])
    error_message = "Only /16 or /21 CIDR notation is accepted."
  }
}

# Set the default region you want to work in
variable "region" {
  description = "The AWS region to use for deployment"
  default     = "us-east-2"
  type        = string
}

# Set the default availability zones
variable "availability_zones" {
  description = "Availability zones to use"
  type        = list(string)
  default     = ["us-east-2a", "us-east-2b"]
}

# Give your project a name
variable "project" {
  description = "Project identifier for resource naming"
  type        = string
  default     = "cyberbear-range"
}


##########################################################################################
# LOCAL VARIABLES
##########################################################################################
locals {
  name_prefix = "${var.project}"

  # Set the cidr block for the server subnets
  public_sub_cidr_block  = "10.0.1.0/24"
  private_sub_cidr_block = "10.0.2.0/24"

}


##########################################################################################
# NETWORK
##########################################################################################
# Creates a VPC (isolated network) with a specific IP range
resource "aws_vpc" "vpc" {
  cidr_block           = var.cidr # IP address range for the VPC
  enable_dns_support   = true     # Enables internal DNS resolution
  enable_dns_hostnames = true     # Enables DNS hostnames for EC2 instances

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

# Creates a PUBLIC subnet within the VPC for publicly available resources
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.vpc.id              # References parent VPC
  cidr_block              = local.public_sub_cidr_block # Subnet's IP range
  availability_zone       = var.availability_zones[0]   # Physical data center location
  map_public_ip_on_launch = true                        # Auto-assigns public IPs to instances -- only use if instance needs to be public, otherwise set to false

  tags = {
    Name = "${local.name_prefix}-public-subnet"
  }
}

# Creates a PRIVATE subnet
resource "aws_subnet" "private_subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = local.private_sub_cidr_block
  availability_zone       = var.availability_zones[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-private-subnet"
  }
}

# Creates an Internet Gateway to allow VPC traffic to reach the internet
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id # Attaches to specified VPC

  tags = {
    Name = "${local.name_prefix}-internet-gateway"
  }
}

# Creates a route table for public subnet
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id # Associates with VPC

  route {
    cidr_block = "0.0.0.0/0"                              # All traffic
    gateway_id = aws_internet_gateway.internet_gateway.id # Routes through internet gateway
  }

  tags = {
    Name = "${local.name_prefix}-public-route-table"
  }
}

# Associate the public route table with the public subnet
resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public_subnet.id           # Subnet to affect
  route_table_id = aws_route_table.public_route_table.id # Route table to use

  depends_on = [aws_subnet.public_subnet]
}


# Code for EIP, NAT Gateway, and route table for private subnet should you chose to use
/*
# Creates an Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc" # indicates if this EIP is for use in VPC 

  tags = {
    Name = "${local.name_prefix}-nat-eip"
  }

  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.internet_gateway]
}

# NAT Gateway
resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_eip.id          # allocate IP address to the NAT Gateway
  subnet_id     = aws_subnet.public_subnet.id # subnet association

  tags = {
    Name = "${local.name_prefix}-nat-gateway"
  }
  
  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.internet_gateway]
}

# Creates a route table for private subnet
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }

  tags = {
    Name = "${local.name_prefix}-private-route-table"
  }
}

# Associate the private route table with the public subnet
resource "aws_route_table_association" "private_rta" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id

  depends_on = [aws_subnet.private_subnet]
}
*/

