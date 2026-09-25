##########################################################################################
# Name: CyberBear Range Template
# Description: Basic AWS infrastructure build-out using Terraform -- consists of a VPC network and EC2 Instances
# Author: Jonathan Kirby
##########################################################################################

##########################################################################################
# VARIABLES
##########################################################################################
# Set the default CIDR block you want to work in 
variable "cidr" {
  description = "The base CIDR block used for the VPC and all subnets" # Documents purpose
  default     = "10.0.0.0/16"                                          # Sets default value
  type        = string                                                 # Data type
  validation {                                                         # Validation conditions and error message if validation fails
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

# Default instance types for Linux servers
variable "lnx_servers_instance_type" {
  description = "The AWS Instance type to use for vanilla Linux systems"
  default     = "t2.micro"
  type        = string
}

# Default instance types for Windows servers
variable "win2025_instance_type" {
  description = "The AWS Instance type to use for vanilla Windows Server 2025"
  default     = "t3.micro"
  type        = string
}

variable "secrets_path" {
  description = "The local path where secrets like a VPN client and SSH keys will be written to"
  default     = "./secrets"
  type        = string
}

##########################################################################################
# PROVIDERS
##########################################################################################
# Configures the AWS provider plugin
provider "aws" {
  region = var.region # Sets AWS region using a variable for flexibility

  # Default tags get applied to all resources
  default_tags {
    tags = {
      Owner   = "CyberRanger" # "Dev", "Infra", "Data", "Security"
      Project = var.project
      # Environment = var.environment
      Provisioned = "Terraform"
      # Are there any other default tags we'd like to add?
    }
  }
}

##########################################################################################
# DATA Sources
##########################################################################################
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

##########################################################################################
# GENERIC RESOURCES
##########################################################################################
resource "random_string" "uid" {
  length  = 5
  special = false
  lower   = true
  upper   = false
  numeric = true
}

##########################################################################################
# LOCAL VARIABLES
##########################################################################################
locals {
  name_prefix = var.project

  # Set the cidr block for the server subnet
  public_sub_cidr_block  = "10.0.1.0/24"
  private_sub_cidr_block = "10.0.2.0/24"

  # Give your CyberBears names.  It helps bring them to life :-)
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
  vpc_id = aws_vpc.vpc.id # Attaches the IG to specified VPC

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

  # Create VPC Flow Log
  resource "aws_flow_log" "flow_logs" {
  log_destination      = aws_s3_bucket.log_bucket.arn # Log destination
  log_destination_type = "s3"                         # Log destination type
  traffic_type         = "ALL"                        # Type of traffic to filter
  vpc_id               = aws_vpc.vpc.id               # VPC to associate flow logs with

  tags = {
      Name = "${local.name_prefix}-flow-logs"
  }

  depends_on = [aws_s3_bucket.log_bucket]
  }

##########################################################################################
# SECURITY
##########################################################################################
# Creates security group and ingress/egress rules (firewall) for instances
resource "aws_security_group" "cyberbear_sg" {
  name = "${local.name_prefix}-security-group"
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

##########################################################################################
# CYBER BEARS
##########################################################################################
#######################################
# Big Bear
#######################################
# Creates EC2 instance
resource "aws_instance" "big_bear" {
  ami                         = data.aws_ami.amazon_linux2023.id     # Amazon Machine Image
  instance_type               = var.lnx_servers_instance_type        # Server size (CPU/memory)
  subnet_id                   = aws_subnet.public_subnet.id          # Network placement
  vpc_security_group_ids      = [aws_security_group.cyberbear_sg.id] # Firewall rules.  Square brackets are used for this input because it takes a list
  private_ip                  = local.big_bear_private_ip            # Private IP assignment
  associate_public_ip_address = true                                 # Auto-assigns public IPs to instances -- only use if instance needs to be public, otherwise set to false
  #ebs_optimized               = true # Optimize ebs for best performance
  #monitoring                  = true  # Use detailed monitoring in production

  # Forces IMDSv2 (required for security)
  #metadata_options {
  #  http_tokens = "required"
  #}

  # Encrypts the root block (required for security)
  #root_block_device {
  #  encrypted = true
  #}

  # Pass inline user-date script directly
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

############################################################################################
# S3 BUCKETS
############################################################################################
########################################
# KMS Keys
########################################
# Create KMS key for encrypting bucket
resource "aws_kms_key" "bucket_key" {
  description             = "This key is used to encrypt bucket objects"
  enable_key_rotation     = true # Enables auto key rotation
  deletion_window_in_days = 7    # 7-30 days
}

resource "aws_kms_alias" "bucket_key_alias" {
  name          = "alias/bucket-key"
  target_key_id = aws_kms_key.bucket_key.key_id
}

# Log bucket
resource "aws_s3_bucket" "log_bucket" {
  bucket = "${local.name_prefix}-log-bucket-${random_string.uid.result}" # bucket name

  force_destroy = true # only use during testing
}

# Bucket Ownership
resource "aws_s3_bucket_ownership_controls" "log_bucket_owner" {
  bucket = aws_s3_bucket.log_bucket.id # Bucket to associate to
  rule {
    object_ownership = "BucketOwnerEnforced" # Defines bucket/object ownership
  }
}

# S3 Public Access Block
# This should be default configuration for all buckets - required for security.  Open up as needed for specific use case.
resource "aws_s3_bucket_public_access_block" "log_bucket_block_public_access" {
  bucket = aws_s3_bucket.log_bucket.id # Bucket to associate to

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enables KMS encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "log_bucket_encryption" {
  bucket = aws_s3_bucket.log_bucket.id # Bucket to associate to

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.bucket_key.arn # KMS key association  
      sse_algorithm     = "aws:kms"                  # Server-side encryption algorithm
    }

    bucket_key_enabled = true # When KMS encryption is used to encrypt new objects in this bucket, the bucket key reduces encryption costs by lowering calls to AWS KMS
  }
}

# Enables bucket versioning
resource "aws_s3_bucket_versioning" "log_bucket_versioning" {
  bucket = aws_s3_bucket.log_bucket.id # Bucket to associate to

  versioning_configuration {
    status = "Enabled"
  }
}

# Enables bucket access logging
resource "aws_s3_bucket_logging" "log_bucket_logging" {
  bucket = aws_s3_bucket.log_bucket.id # Bucket to associate to

  target_bucket = aws_s3_bucket.log_bucket.id # Target bucket where you're sending logs to
  target_prefix = "access-logs/"              # Send logs to folder with the target prefix
}

# Force SSL to access bucket
resource "aws_s3_bucket_policy" "log_force_ssl_bucket_policy" {
  bucket = aws_s3_bucket.log_bucket.id # Bucket to associate to

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "ForceSSLOnlyAccess"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        "${aws_s3_bucket.log_bucket.arn}/*",
        "${aws_s3_bucket.log_bucket.arn}"
      ],
      Condition = {
        Bool = {
          "aws:SecureTransport" = "false"
        }
      }
    }]
  })
}

# Enables and sets bucket data lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "log_bucket_config" {
  bucket = aws_s3_bucket.log_bucket.id # Bucket to associate to

  rule {
    id = "logs"

    status = "Enabled" # Enabled or Disabled

    abort_incomplete_multipart_upload {
      days_after_initiation = 1 # number
    }

    expiration {
      days = 365 # integer > 0
    }

    transition {
      days          = 30            # integer >= 0
      storage_class = "STANDARD_IA" # string/enum, one of GLACIER, STANDARD_IA, ONEZONE_IA, INTELLIGENT_TIERING, DEEP_ARCHIVE, GLACIER_IR.
    }

    transition {
      days          = 60        # integer >= 0
      storage_class = "GLACIER" # string/enum, one of GLACIER, STANDARD_IA, ONEZONE_IA, INTELLIGENT_TIERING, DEEP_ARCHIVE, GLACIER_IR.
    }

    noncurrent_version_expiration {
      newer_noncurrent_versions = 3  # integer > 0
      noncurrent_days           = 60 # integer >= 0
    }

    noncurrent_version_transition {
      newer_noncurrent_versions = 3         # integer >= 0
      noncurrent_days           = 30        # integer >= 0
      storage_class             = "GLACIER" # string/enum, one of GLACIER, STANDARD_IA, ONEZONE_IA, INTELLIGENT_TIERING, DEEP_ARCHIVE, GLACIER_IR.
    }
  }
}

##########################################################################################
# OUTPUTS
##########################################################################################
output "ssh_private_key" {
  description = "The SSH private key used to access linux based systems"
  value       = module.ssh_key_pair.private_key
  sensitive   = true
}

output "ssh_public_key" {
  description = "The SSH public key that belongs to the private key"
  value       = module.ssh_key_pair.public_key
}

locals {
  ssh_prefix = "ssh -i ${module.ssh_key_pair.private_key_filename}"

  output_connect_cheat_sheet = <<CONFIG
     big_bear: ${local.ssh_prefix} ec2-user@${aws_instance.big_bear.public_ip}
  CONFIG

}

output "zdetails" {
  description = "Helpful details about the range"
  value       = <<EOF
 The range has been built successfully, below are useful details for using the range.

 Connection Cheat Sheet
 --------------------------------------------------------------------------------------
 ${local.output_connect_cheat_sheet}

 ==============================================
 ===   Build-A-CyberBear Heart Ceremony     ===
 ==============================================

 Rub your heart with your hands so your cloud has a warm heart.

 Rub your head so your cloud is smart like you.

 Rub your nose so the cloud knows who you are.

 Rub your back so it will always have your back and protect you.

 Shake your hands up high in the air to give your CyberBear Range high hopes to explore and learn great things.

 Jump up and down to get the CyberBear Range heart pumping.

 Give your heart a kiss, close your eyes and make a wish.

 ==============================================
 ==============================================

 Hosts
 --------------------------------------------------------------------------------------
 big_bear: 
    public ip: ${aws_instance.big_bear.public_ip}
   private ip: ${local.big_bear_private_ip}
           -->  ${local.ssh_prefix} ec2-user@${aws_instance.big_bear.public_ip}

 S3 Bucket
 --------------------------------------------------------------------------------------
 ${aws_s3_bucket.log_bucket.id}

 --------------------------------------------------------------------------------------
 Have fun with your new CyberBear Range!

 What will you build next?

 EOF
}