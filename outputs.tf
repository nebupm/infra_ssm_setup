#########################################################
# VPC + SUBNETS
#########################################################

output "vpc_id" {
  description = "Details of the main VPC"
  value = {
    name = aws_vpc.this_vpc.tags.Name
    id   = aws_vpc.this_vpc.id
    cidr = aws_vpc.this_vpc.cidr_block
  }
}

output "public_subnet_id" {
  description = "Details of the main public subnet"
  value = {
    name = aws_subnet.this_public_subnet.tags.Name
    id   = aws_subnet.this_public_subnet.id
    cidr = aws_subnet.this_public_subnet.cidr_block
  }
}

output "private_subnet_id" {
  description = "Details of the main private subnet"
  value = {
    name = aws_subnet.this_private_subnet.tags.Name
    id   = aws_subnet.this_private_subnet.id
    cidr = aws_subnet.this_private_subnet.cidr_block
  }
}

#########################################################
# SECURITY GROUPS
#########################################################
output "instance_security_group_id" {
  description = "Security Group ID used by the EC2 instance"
  value       = aws_security_group.this_sg.id
}
output "vpc_endpoints_security_group_id" {
  description = "Security Group ID used by the VPC Endpoints"
  value       = aws_security_group.vpc_endpoints_sg.id
}

#########################################################
# EC2 INSTANCE
#########################################################
output "instance_id" {
  description = "ID of the EC2 instance"
  value = {
    id            = aws_instance.local_vm_server.id
    name          = aws_instance.local_vm_server.tags.Name
    public_ip     = aws_instance.local_vm_server.public_ip
    private_ip    = aws_instance.local_vm_server.private_ip
    ami           = aws_instance.local_vm_server.ami
    instance_type = aws_instance.local_vm_server.instance_type
  }
}

output "instance_iam_role" {
  description = "IAM role attached to the EC2 instance"
  value       = aws_iam_role.ec2_ssm_role.name
}

#########################################################
# NAT GATEWAY + INTERNET
#########################################################
output "nat_gateway_id" {
  description = "Details of the NAT Gateway"
  value = {
    id         = aws_nat_gateway.this_nat_gw.id
    subnet_id  = aws_nat_gateway.this_nat_gw.subnet_id
    allocation = aws_nat_gateway.this_nat_gw.allocation_id
    network_ip = aws_nat_gateway.this_nat_gw.network_interface_id
  }
}

output "nat_gateway_public_ip" {
  description = "Public IP address of the NAT Gateway"
  value = {
    public_ip     = aws_eip.this_nat_eip.public_ip
    allocation_id = aws_eip.this_nat_eip.id
    igw_gw_id     = aws_internet_gateway.this_igw.id
  }
}

#########################################################
# VPC SSM ENDPOINTS
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
