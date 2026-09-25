##########################################################################################
# VARIABLES
##########################################################################################
variable "secrets_path" {
  description = "The local path where secrets like a VPN client and SSH keys will be written to"
  default     = "./secrets"
  type        = string
}

# Default instance types for Linux servers
variable "lnx_servers_instance_type" {
  description = "The AWS Instance type to use for vanilla Linux systems"
  default     = "t2.micro"
  type        = string
}

# Default instance types for Windows servers
variable "win_servers_instance_type" {
  description = "The AWS Instance type to use for vanilla Windows Servers"
  default     = "t3.micro"
  type        = string
}


############################################################################################
# DATA SOURCES
############################################################################################
# Use Data sources to lookup AWS resources to use in your environment
data "aws_ami" "ubuntu24" {
  most_recent = true
  owners      = ["099720109477"] // Owner for the vanilla Ubuntu (Canonical)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"] // Vanilla AWS Ubuntu 24.04 LTS
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_ami" "amazon_linux2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"] // Vanilla AWS Amazon Linux 2023
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_ami" "win2025" {
  most_recent = true
  owners      = ["801119661308"] // Owner for the Vanilla AWS Windows Server

  filter {
    name   = "name"
    values = ["Windows_Server-2025-English-Full-Base-*"] // Vanilla AWS Windows Server 2025
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}


############################################################################################
# LOCAL VARIABLES
############################################################################################
locals {

  # Give your bears names.  It helps bring them to life :-)
  # SERVER HOSTS IP/HOSTNAME
  big_bear_hostname   = "big_bear"
  big_bear_private_ip = cidrhost(local.public_sub_cidr_block, 10)

}

##########################################################################################
# AWS SSH KEYPAIR
##########################################################################################
// Source: https://github.com/cloudposse/terraform-aws-key-pair
module "ssh_key_pair" {
  source                = "git::github.com/cloudposse/terraform-aws-key-pair"
  ssh_public_key_path   = var.secrets_path
  generate_ssh_key      = "true"
  private_key_extension = ".pem"
  public_key_extension  = ".pub"

}


##########################################################################################
# SECURITY
##########################################################################################
# Creates security group and ingress/egress rules (firewall) for instances
resource "aws_security_group" "cyberbear_sg" {
  name        = "${local.name_prefix}-security-group"
  # Add simple description for the Security Group
  description = "Allow SSH, HTTP, and HTTPS from the world"
  vpc_id      = aws_vpc.vpc.id
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh" {
  description       = "Allow SSH from anywhere"
  security_group_id = aws_security_group.cyberbear_sg.id
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp" 
  cidr_ipv4         = "0.0.0.0/0" # Source IPs (any) - This is the same as global allow and should only be used with ports 80 & 443
  # Security Group ingress cidr blocks should be restricted to the specific IPs required for the service
  # Only setting ssh global allow for playground purposes; NEVER set global allow ssh in production

  tags = {
    Name = "allow-ssh"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_http" {
  description       = "Allow HTTP from anywhere"
  security_group_id = aws_security_group.cyberbear_sg.id
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp" 
  cidr_ipv4         = "0.0.0.0/0" # Source IPs (any) - This is the same as global allow and should only be used with ports 80 & 443
  # Security Group ingress cidr blocks should be restricted to the specific IPs required for the service

  tags = {
    Name = "allow-http"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_https" {
  description       = "Allow HTTPS from anywhere"
  security_group_id = aws_security_group.cyberbear_sg.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp" 
  cidr_ipv4         = "0.0.0.0/0" # Source IPs (any) - This is the same as global allow and should only be used with ports 80 & 443
  # Security Group ingress cidr blocks should be restricted to the specific IPs required for the service

  tags = {
    Name = "allow-https"
  }
}

resource "aws_vpc_security_group_egress_rule" "allow_all" {
  description       = "Allow all outbound traffic"
  security_group_id = aws_security_group.cyberbear_sg.id
  ip_protocol       = "-1"        # semantically equivalent to all ports
  cidr_ipv4         = "0.0.0.0/0" # All destinations
  # In production, egress rules should be restricted to ports/protocols needed for specific business use case

  tags = {
    Name = "allow-all-egress"
  }
}


############################################################################################
# CYBER BEARS
############################################################################################
# Creates EC2 instance (virtual server)
resource "aws_instance" "big_bear" {
  ami                         = data.aws_ami.amazon_linux2023.id              # Amazon Machine Image
  instance_type               = var.lnx_servers_instance_type                 # Server size (CPU/memory)
  subnet_id                   = aws_subnet.public_subnet.id                   # Network placement
  vpc_security_group_ids      = [aws_security_group.cyberbear_sg.id] # Firewall rules.  Square brackets used for this input because it takes a list
  private_ip                  = local.big_bear_private_ip                     # Private IP assignment
  associate_public_ip_address = true                                          # Auto-assigns public IPs to instances -- only use if instance needs to be public, otherwise set to false
  #ebs_optimized               = true                                          # Optimize ebs for best performance
  #monitoring                  = true                                          # Use detailed monitoring in production

  # Forces IMDSv2 (required for security)
  #metadata_options {
  #  http_tokens = "required"
  #}

  # Encrypts the root block (required for security)
  #root_block_device {
  #  encrypted = true
  #}

  # Pass inline shell script directly
  user_data = <<-EOF
    #!/bin/bash
    sudo yum update -y
    sudo yum install httpd -y
    sudo systemctl start httpd
    sudo systemctl enable httpd
    cd /var/www/html
    echo "<html><h1>Hello Cloud Rangers. Welcome to the ${local.big_bear_hostname} webpage.</h1></html>" > index.html
    EOF

  tags = {
    Name = "${local.name_prefix}-${local.big_bear_hostname}"
  }

  depends_on = [aws_subnet.public_subnet]
}

