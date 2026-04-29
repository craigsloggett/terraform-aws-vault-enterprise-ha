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

variable "vault_enterprise_license" {
  type        = string
  description = "Vault Enterprise license string."
  sensitive   = true
}

variable "ec2_key_pair_name" {
  type        = string
  description = "Name of an existing EC2 key pair for SSH access."
}

variable "hcp_terraform_jwt_auth" {
  description = <<-EOT
    Configuration for the HCP Terraform JWT auth method that provides
    dynamic, short-lived Vault credentials to HCP Terraform workspaces.
    When `organization_name` and `workspace_id` are set, a JWT auth method
    is mounted at `mount_path` in the root namespace and configured to
    verify tokens against `hostname` via OIDC discovery. A role named
    `role_name` is created against that mount with `bound_claims`
    restricting authentication to the declared organization and workspace.
  EOT
  default     = {}
  type = object({
    hostname              = optional(string, "app.terraform.io")
    organization_name     = optional(string, "")
    workspace_id          = optional(string, "")
    oidc_discovery_ca_pem = optional(string, "")
    mount_path            = optional(string, "app-terraform-io")
    role_name             = optional(string, "terraform-admin")
  })
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
  description = "Size in GiB of the root EBS volume for Vault nodes."
  default     = 50

  validation {
    condition     = var.root_volume_size >= 20
    error_message = "Root volume must be at least 20 GiB."
  }
}

variable "vault_data_disk" {
  type = object({
    volume_type = optional(string, "gp3")
    volume_size = optional(number, 50)
    iops        = optional(number, 3000)
    throughput  = optional(number, 125)
  })
  description = "EBS configuration for the Vault Raft Data storage volume (/dev/xvdf)."
  default = {
    volume_type = "gp3"
    volume_size = 50
    iops        = 3000
    throughput  = 125
  }
}

variable "vault_audit_disk" {
  type = object({
    volume_type = optional(string, "gp3")
    volume_size = optional(number, 50)
  })
  description = "EBS configuration for the Vault Audit Log storage volume (/dev/xvdg)."
  default = {
    volume_type = "gp3"
    volume_size = 50
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

# AWS Auth

variable "vault_aws_auth_role_max_ttl" {
  type        = string
  description = "Max TTL for the vault-server AWS auth role."
  default     = "24h"
}

variable "vault_aws_auth_role_ttl" {
  type        = string
  description = "Default TTL for the vault-server AWS auth role."
  default     = "4h"
}

# JWT Auth

variable "vault_jwt_auth_role_max_ttl" {
  type        = string
  description = "Max TTL for the HCP Terraform JWT auth role."
  default     = "2h"
}

variable "vault_jwt_auth_role_ttl" {
  type        = string
  description = "Default TTL for the HCP Terraform JWT auth role."
  default     = "1h"
}

# PKI

variable "vault_pki_intermediate_ca" {
  description = "Configuration for the Vault PKI intermediate CA certificate."
  default     = {}
  type = object({
    common_name  = optional(string, "Vault Intermediate CA")
    country      = optional(string, "")
    organization = optional(string, "")
    key_type     = optional(string, "rsa")
    key_bits     = optional(number, 2048)
  })

  validation {
    condition     = contains(["ec", "rsa"], var.vault_pki_intermediate_ca.key_type)
    error_message = "key_type must be \"ec\" or \"rsa\"."
  }

  validation {
    condition     = var.vault_pki_intermediate_ca.key_type != "ec" || contains([224, 256, 384, 521], var.vault_pki_intermediate_ca.key_bits)
    error_message = "key_bits for ec must be 224, 256, 384, or 521."
  }

  validation {
    condition     = var.vault_pki_intermediate_ca.key_type != "rsa" || contains([2048, 3072, 4096, 8192], var.vault_pki_intermediate_ca.key_bits)
    error_message = "key_bits for rsa must be 2048, 3072, 4096, or 8192."
  }
}

variable "vault_pki_signed_intermediate_wait_timeout_seconds" {
  type        = number
  description = "Maximum seconds the bootstrap node waits for the signed intermediate certificate to appear in Secrets Manager."
  default     = 1800
}

variable "vault_pki_vault_mount_max_ttl" {
  type        = string
  description = "Max lease TTL for the Vault PKI secrets engine mount."
  default     = "26280h"
}

variable "vault_pki_vault_server_role_max_ttl" {
  type        = string
  description = "Max TTL for certificates issued by the vault-server PKI role."
  default     = "24h"
}

variable "vault_pki_server_cert_ttl" {
  type        = string
  description = "TTL requested when the bootstrap script issues the Vault server certificate."
  default     = "24h"
}

variable "vault_pki_mount_path" {
  type        = string
  description = "Mount path for the Vault PKI secrets engine used to issue Vault server TLS certificates."
  default     = "pki_vault"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.vault_pki_mount_path))
    error_message = "vault_pki_mount_path must contain only alphanumeric characters, underscores, and hyphens."
  }
}

# IAM

variable "vault_server_iam_resource_names" {
  description = <<-EOT
    Names for the IAM resources created by this module. Each field is optional;
    consumers are expected to set these to environment-appropriate values to
    avoid collisions when deploying multiple instances of the module into the
    same AWS account. Switching a name (or accepting a new default) replaces
    the underlying AWS resource since IAM resource names are immutable.
  EOT
  default     = {}
  type = object({
    role                              = optional(string, "VaultServerInstanceRole")
    instance_profile                  = optional(string, "VaultServerInstanceProfile")
    kms_read_write_policy             = optional(string, "VaultServerKMSReadWriteAccess")
    kms_describe_policy               = optional(string, "VaultServerKMSDescribeAccess")
    secrets_manager_read_policy       = optional(string, "VaultServerSecretsManagerReadOnlyAccess")
    secrets_manager_describe_policy   = optional(string, "VaultServerSecretsManagerDescribeAccess")
    secrets_manager_read_write_policy = optional(string, "VaultServerSecretsManagerReadWriteAccess")
    s3_read_write_policy              = optional(string, "VaultServerS3ObjectReadWriteAccess")
    s3_list_policy                    = optional(string, "VaultServerS3BucketListAccess")
    ec2_describe_policy               = optional(string, "VaultServerEC2DescribeAccess")
    ssm_read_write_policy             = optional(string, "VaultServerSSMReadWriteAccess")
    iam_read_policy                   = optional(string, "VaultServerIAMReadOnlyAccess")
  })
}
