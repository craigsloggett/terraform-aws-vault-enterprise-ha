# Required

variable "project_name" {
  type        = string
  description = "Name prefix for all resources."
}

variable "route53_zone_name" {
  type        = string
  description = "Name of the existing Route 53 hosted zone."
}

variable "vault_license" {
  type        = string
  description = "Vault Enterprise license string."
  sensitive   = true
}

variable "ec2_key_pair_name" {
  type        = string
  description = "Name of an existing EC2 key pair for SSH access."
}

# General

variable "common_tags" {
  type        = map(string)
  description = "Tags to apply to all resources."
  default     = {}
}

# VPC

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "vpc_private_subnets" {
  type        = list(string)
  description = "Private subnet CIDR blocks."
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "vpc_public_subnets" {
  type        = list(string)
  description = "Public subnet CIDR blocks."
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

# EC2

variable "ec2_instance_ami_id" {
  type        = string
  description = "AMI ID to use for EC2 instances. Must be Ubuntu or Debian-based."
}

variable "vault_instance_type" {
  type        = string
  description = "EC2 instance type for Vault nodes."
  default     = "m5.large"
}

variable "vault_ebs_volume_size" {
  type        = number
  description = "Size in GiB of the EBS volume for Vault Raft storage."
  default     = 100
}

variable "bastion_instance_type" {
  type        = string
  description = "EC2 instance type for the bastion host."
  default     = "t3.micro"
}

variable "bastion_allowed_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to SSH to the bastion host."
  default     = ["0.0.0.0/0"]
}

# Vault

variable "vault_subdomain" {
  type        = string
  description = "Subdomain for the Vault DNS record."
  default     = "vault"
}

variable "vault_package_version" {
  type        = string
  description = "Vault Enterprise apt package version to install (e.g., 1.21.4+ent-1)."
  default     = "1.21.4+ent-1"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+\\+ent(\\.hsm)?(\\.fips1403)?-\\d+$", var.vault_package_version))
    error_message = "Must be a valid Vault Enterprise package version (e.g., 1.21.4+ent-1, 1.21.4+ent.hsm.fips1403-1)."
  }
}

# NLB

variable "nlb_internal" {
  type        = bool
  description = "Whether the NLB is internal."
  default     = true
}
