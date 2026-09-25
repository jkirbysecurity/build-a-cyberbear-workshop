# Specifies Terraform configuration including required providers
terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws" # Provider namespace and type
      version = "~> 6.66.0"     # Allows patch updates but not minor version changes
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }
  }
}