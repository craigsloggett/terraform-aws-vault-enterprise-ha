# Required

variable "project_name" {
  type        = string
  description = "Name prefix for all resources."

  validation {
    condition     = length(var.project_name) <= 16
    error_message = "Must be 16 characters or fewer to fit within the 63-character S3 bucket name limit."
  }
}

variable "route53_zone" {
  type = object({
    zone_id = string
    name    = string
  })
  description = "Route 53 hosted zone for the Vault DNS record."
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

variable "existing_vpc" {
  type = object({
    vpc_id             = string
    private_subnet_ids = list(string)
    public_subnet_ids  = list(string)
  })
  default     = null
  description = <<-EOT
    Existing VPC to deploy into. When null (default), a new VPC is created.
    The existing VPC must already have the required VPC endpoints:
    Secrets Manager, KMS, and EC2 (Interface), S3 (Gateway).
  EOT

  validation {
    condition     = var.existing_vpc == null || (length(var.existing_vpc.private_subnet_ids) > 0 && length(var.existing_vpc.public_subnet_ids) > 0)
    error_message = "existing_vpc subnet ID lists must be non-empty."
  }
}

# EC2

variable "ec2_ami" {
  type = object({
    id   = string
    name = string
  })
  description = "AMI to use for EC2 instances. Must be Ubuntu or Debian-based."
}

variable "vault_node_count" {
  type        = number
  description = "Number of Vault nodes in the cluster. Must be 3 or 5 for Raft quorum."
  default     = 3

  validation {
    condition     = contains([3, 5], var.vault_node_count)
    error_message = "Must be 3 or 5."
  }
}

variable "vault_server_instance_type" {
  type        = string
  description = "EC2 instance type for Vault server nodes."
  default     = "m5.large"
}

variable "root_volume_size" {
  type        = number
  description = "Size in GiB of the root EBS volume for Vault nodes. Raft data is stored here when no separate data volume is attached."
  default     = 50

  validation {
    condition     = var.root_volume_size >= 20
    error_message = "Root volume must be at least 20 GiB."
  }
}

variable "vault_audit_disk" {
  type = object({
    volume_type = string
    volume_size = number
    encrypted   = bool
  })
  description = "EBS configuration for the Vault audit log volume (/dev/xvdg)."
  default = {
    volume_type = "gp3"
    volume_size = 50
    encrypted   = true
  }
}

variable "bastion_instance_type" {
  type        = string
  description = "EC2 instance type for the bastion host."
  default     = "t3.micro"
}

variable "bastion_allowed_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to SSH to the bastion host. Defaults to 0.0.0.0/0 for convenience; restrict to known ranges in any production deployment."
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for cidr in var.bastion_allowed_cidrs : can(cidrhost(cidr, 0))])
    error_message = "All entries must be valid CIDR blocks."
  }
}

# Vault

variable "vault_subdomain" {
  type        = string
  description = "Subdomain for the Vault DNS record."
  default     = "vault"
}

variable "vault_version" {
  type        = string
  description = "Vault Enterprise release version (e.g., 1.21.4+ent)."
  default     = "1.21.4+ent"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+\\+ent(\\.hsm)?(\\.fips1402)?$", var.vault_version))
    error_message = "Must be a valid Vault Enterprise release version (e.g., 1.21.4+ent, 1.21.4+ent.hsm, 1.21.4+ent.fips1402)."
  }
}

# NLB

variable "nlb_internal" {
  type        = bool
  description = "Whether the NLB is internal."
  default     = true
}

variable "vault_api_allowed_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the Vault API (port 8200) from outside the VPC. Only effective when nlb_internal is false."
  default     = []
}

# Snapshots

variable "vault_snapshot_interval" {
  type        = number
  description = "Seconds between automated Raft snapshots."
  default     = 3600

  validation {
    condition     = var.vault_snapshot_interval >= 60
    error_message = "Must be at least 60 seconds."
  }
}

variable "vault_snapshot_retain" {
  type        = number
  description = "Number of automated Raft snapshots to retain in S3."
  default     = 72

  validation {
    condition     = var.vault_snapshot_retain >= 1
    error_message = "Must retain at least 1 snapshot."
  }
}
