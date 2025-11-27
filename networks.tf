#########################################################
#This will create a VPC, Subnets, IGW, Routing tables and Security Groups.
#########################################################
# VARIABLES
#########################################################
# Define the region for AWS resources
variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "eu-west-2"
}
# Define the region for AWS resources
variable "aws_profile" {
  description = "The AWS profile to use for running the code"
  type        = string
  default     = "default"
}

# VPC and Networking Variables
variable "vpc_name" {
  type        = string
  description = "VPC Name"
  default     = "main-vpc-ssm"
}
variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR values"
  default     = "10.0.0.0/16"
}

#########################################################
# NETWORK RESOURCES
#########################################################
# Setup main vpc
resource "aws_vpc" "this_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.vpc_name }
}

#Setup public subnet for NAT Gateway.
resource "aws_subnet" "this_public_subnet" {
  vpc_id     = aws_vpc.this_vpc.id
  cidr_block = "10.0.1.0/24"
  tags       = { Name = "${var.vpc_name}-public-subnet" }
}

# Setup private subnet for EC2 instance.
resource "aws_subnet" "this_private_subnet" {
  vpc_id     = aws_vpc.this_vpc.id
  cidr_block = "10.0.0.0/24"
  tags       = { Name = "${var.vpc_name}-private-subnet" }
}

# Internet Gateway
resource "aws_internet_gateway" "this_igw" {
  vpc_id = aws_vpc.this_vpc.id
  tags   = { Name = "${var.vpc_name}-igw" }
}

# NAT Gateway EIP
resource "aws_eip" "this_nat_eip" {
  tags       = { Name = "${var.vpc_name}-nat-gw-eip" }
  depends_on = [aws_internet_gateway.this_igw]
}

# NAT Gateway
resource "aws_nat_gateway" "this_nat_gw" {
  allocation_id = aws_eip.this_nat_eip.id
  subnet_id     = aws_subnet.this_public_subnet.id
  tags          = { Name = "${var.vpc_name}-nat-gw" }
}

# Public Route Table
resource "aws_route_table" "this_public_route_table" {
  vpc_id = aws_vpc.this_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this_igw.id
  }
  tags = { Name = "${var.vpc_name}-public-rt" }
}

resource "aws_route_table_association" "this_public_route_table_association" {
  subnet_id      = aws_subnet.this_public_subnet.id
  route_table_id = aws_route_table.this_public_route_table.id
}

# Private Route Table
# EC2 subnet (10.0.0.0/24) must route 0.0.0.0/0 → NAT Gateway
resource "aws_route_table" "this_private_route_table" {
  vpc_id = aws_vpc.this_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this_nat_gw.id
  }
  tags = { Name = "${var.vpc_name}-private-rt" }
}

resource "aws_route_table_association" "this_private_route_table_association" {
  subnet_id      = aws_subnet.this_private_subnet.id # your EC2 subnet
  route_table_id = aws_route_table.this_private_route_table.id
}

resource "aws_security_group" "ec2_instance_sg" {
  name        = "${var.vpc_name}-ec2-inst-sg"
  description = "Security group for EC2 Instances in ${var.vpc_name}"
  vpc_id      = aws_vpc.this_vpc.id

  # Allow RDP for Windows / SSH for Linux only from your IP (optional)
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["82.16.60.106/32"]
  }
  # Allow SMB port for FSx communication
  ingress {
    from_port   = 445
    to_port     = 445
    protocol    = "tcp"
    cidr_blocks = ["82.16.60.106/32"]
  }
  # Allow SSH communication.
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["82.16.60.106/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.vpc_name}-ec2-inst-sg" }
}

###############################################################################
# IAM ROLE + INSTANCE PROFILE for SSM
###############################################################################
resource "aws_iam_role" "ec2_ssm_role" {
  name                 = "AllowSSMRoleToAccessInstances"
  description          = "Custom - Role to allow EC2 instances to use SSM Service features"
  max_session_duration = 7200
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}
# Attach the AmazonSSMManagedInstanceCore policy to the role. The policy for Amazon EC2 Role to enable AWS Systems Manager service core functionality. 
resource "aws_iam_role_policy_attachment" "ssm_role_attach" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2-instance-profile-for-ssm" {
  name = "ec2-instance-profile-for-ssm"
  role = aws_iam_role.ec2_ssm_role.name
}

###############################################################################
# VPC INTERFACE ENDPOINTS (SSM)
###############################################################################
locals {
  ssm_endpoints = [
    "ssm",
    "ec2messages",
    "ssmmessages"
  ]
}

# use the endpoint SG on the endpoint ENIs
resource "aws_vpc_endpoint" "vpc_ssm_endpoints" {
  for_each            = toset(local.ssm_endpoints)
  vpc_id              = aws_vpc.this_vpc.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.this_private_subnet.id]
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true

  tags = { Name = "${var.vpc_name}-${each.key}-endpoint" }
}

# endpoint security group: allow EC2 SG to talk to VPC endpoints on 443
resource "aws_security_group" "vpc_endpoints_sg" {
  name   = "vpc-endpoints-ssm-sg"
  tags   = { Name = "${var.vpc_name}-endpoint-sg" }
  vpc_id = aws_vpc.this_vpc.id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_instance_sg.id] # allow EC2 instances in this SG
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#########################################################
# OUTPUTS - VPC and SUBNETS
#########################################################

output "vpc_name" {
  description = "Details of the main VPC"
  value       = aws_vpc.this_vpc.tags.Name
}

output "public_subnet_name" {
  description = "Details of the main public subnet"
  value       = aws_subnet.this_public_subnet.tags.Name
}

output "private_subnet_name" {
  description = "Details of the main private subnet"
  value       = aws_subnet.this_private_subnet.tags.Name
}

#########################################################
# OUTPUTS - Instance IAM Role Name
#########################################################
output "instance_iam_role" {
  description = "IAM role attached to the EC2 instance"
  value       = aws_iam_role.ec2_ssm_role.name
}

#########################################################
# OUTPUTS - SECURITY GROUPS
#########################################################
output "ec2_instance_security_group_name" {
  description = "Security Group used by the EC2 instance"
  value       = aws_security_group.ec2_instance_sg.name
}
output "vpc_endpoints_security_group_name" {
  description = "Security Group used by the VPC Endpoints"
  value       = aws_security_group.vpc_endpoints_sg.name
}

#########################################################
# OUTPUTS - NAT GATEWAY + INTERNET
#########################################################
output "nat_gateway_id" {
  description = "Details of the NAT Gateway"
  value       = aws_nat_gateway.this_nat_gw.tags.Name
}

output "nat_gateway_public_ip" {
  description = "Public IP address of the NAT Gateway"
  value       = aws_eip.this_nat_eip.public_ip
}

#########################################################
# OUTPUTS - VPC SSM ENDPOINTS
#########################################################
output "ssm_vpc_endpoints" {
  description = "Map of SSM VPC endpoint IDs"
  value = {
    for key, ep in aws_vpc_endpoint.vpc_ssm_endpoints :
    key => ep.id
  }
}

output "ssm_vpc_endpoint_dns" {
  description = "DNS names for SSM VPC endpoints"
  value = {
    for key, ep in aws_vpc_endpoint.vpc_ssm_endpoints :
    key => ep.dns_entry[*].dns_name
  }
}
