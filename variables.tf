variable "project_name" {
  type        = string
  description = "Name prefix for all resources."

  validation {
    condition     = length(var.project_name) <= 16
    error_message = "Must be 16 characters or fewer to fit within the 63-character S3 bucket name limit."
  }
}

variable "vault_enterprise_license" {
  type        = string
  description = "Vault Enterprise license string."
  sensitive   = true
}

variable "ami" {
  type = object({
    id   = string
    name = string
  })
  description = "AMI for EC2 instances. Must be Ubuntu or Debian-based. Accepts the result of an aws_ami data source directly."
}

variable "key_pair" {
  type = object({
    key_name = string
  })
  description = "EC2 key pair for SSH access. Accepts the result of an aws_key_pair data source directly."
}

variable "route53_zone" {
  type = object({
    zone_id = string
    name    = string
  })
  description = "Route 53 hosted zone for the Vault DNS record. Accepts the result of an aws_route53_zone data source directly."
}

variable "vpc" {
  type = object({
    name            = optional(string, "vault-enterprise-vpc")
    cidr            = optional(string, "10.0.0.0/16")
    private_subnets = optional(list(string), ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"])
    public_subnets  = optional(list(string), ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"])
    existing = optional(object({
      vpc_id             = string
      private_subnet_ids = list(string)
      public_subnet_ids  = list(string)
    }), null)
  })
  default     = {}
  description = <<-EOT
    VPC configuration. When `existing` is null (default), a new VPC is created
    using `cidr`, `private_subnets`, and `public_subnets`. When `existing` is
    set, those creation fields are ignored and the supplied VPC is used; it
    must already have the required VPC endpoints (Secrets Manager, KMS, EC2
    Interface; S3 Gateway).
  EOT

  validation {
    condition     = var.vpc.existing == null || (length(var.vpc.existing.private_subnet_ids) > 0 && length(var.vpc.existing.public_subnet_ids) > 0)
    error_message = "vpc.existing subnet ID lists must be non-empty when existing is set."
  }
}

variable "vpc_endpoints" {
  type = object({
    secretsmanager_name = optional(string, "vault-enterprise-secretsmanager-vpc-endpoint")
    kms_name            = optional(string, "vault-enterprise-kms-vpc-endpoint")
    ec2_name            = optional(string, "vault-enterprise-ec2-vpc-endpoint")
    s3_name             = optional(string, "vault-enterprise-s3-vpc-endpoint")
  })
  default     = {}
  description = <<-EOT
    Configuration for the VPC endpoints created by this module (Secrets Manager,
    KMS, EC2 Interface, S3 Gateway). Only created when `vpc.existing` is null;
    when using an existing VPC, endpoints must be provisioned separately.
  EOT
}

variable "bastion" {
  type = object({
    name          = optional(string, "vault-enterprise-bastion-host")
    instance_type = optional(string, "t3.micro")
    allowed_cidrs = optional(list(string), ["0.0.0.0/0"])
  })
  default     = {}
  description = <<-EOT
    Bastion host configuration. `allowed_cidrs` defaults to 0.0.0.0/0 for lab
    convenience; restrict to known ranges in any production deployment.
  EOT

  validation {
    condition     = alltrue([for cidr in var.bastion.allowed_cidrs : can(cidrhost(cidr, 0))])
    error_message = "bastion.allowed_cidrs entries must be valid CIDR blocks."
  }
}

variable "vault_enterprise_servers" {
  type = object({
    instance_name    = optional(string, "vault-enterprise-server")
    volume_name      = optional(string, "vault-enterprise-server-volume")
    instance_type    = optional(string, "m5.large")
    node_count       = optional(number, 3)
    root_volume_size = optional(number, 50)
    raft_data_disk = optional(object({
      volume_type = optional(string, "gp3")
      volume_size = optional(number, 50)
      iops        = optional(number, 3000)
      throughput  = optional(number, 125)
    }), {})
    audit_disk = optional(object({
      volume_type = optional(string, "gp3")
      volume_size = optional(number, 50)
    }), {})
    cluster_auto_join_tag = object({
      key   = optional(string, "vault:raft:retryjoin:autojoin")
      value = string
    })
  })
  description = "Configuration for the Vault Enterprise server EC2 instances and their EBS volumes."

  validation {
    condition     = contains([3, 5], var.vault_enterprise_servers.node_count)
    error_message = "vault_enterprise_servers.node_count must be 3 or 5 for Raft quorum."
  }

  validation {
    condition     = var.vault_enterprise_servers.root_volume_size >= 20
    error_message = "vault_enterprise_servers.root_volume_size must be at least 20 GiB."
  }

  validation {
    condition     = length(var.vault_enterprise_servers.cluster_auto_join_tag.value) > 0
    error_message = "vault_enterprise_servers.cluster_auto_join_tag.value must be a non-empty string to prevent accidentally joining an existing cluster."
  }
}

variable "nlb" {
  type = object({
    internal          = optional(bool, true)
    api_allowed_cidrs = optional(list(string), [])
  })
  default     = {}
  description = <<-EOT
    NLB configuration for the Vault API. `api_allowed_cidrs` is only effective
    when `internal` is false.
  EOT

  validation {
    condition     = alltrue([for cidr in var.nlb.api_allowed_cidrs : can(cidrhost(cidr, 0))])
    error_message = "nlb.api_allowed_cidrs entries must be valid CIDR blocks."
  }
}

variable "kms_key" {
  type = object({
    name = optional(string, "vault-enterprise-auto-unseal-key")
  })
  default     = {}
  description = "Configuration for the KMS key used for Vault auto-unseal."
}

variable "security_groups" {
  type = object({
    bastion_name_prefix       = optional(string, "vault-enterprise-bastion-sg-")
    vault_servers_name_prefix = optional(string, "vault-enterprise-servers-sg-")
    vpc_endpoints_name_prefix = optional(string, "vault-enterprise-vpc-endpoints-sg-")
  })
  default     = {}
  description = <<-EOT
    Name prefixes for the security groups created by this module. The AWS
    provider appends a random suffix to guarantee uniqueness, which enables
    create_before_destroy for security group replacements.
  EOT
}

variable "iam_role" {
  type = object({
    name = optional(string, "VaultEnterpriseServerRole")
    path = optional(string, "/")
    inline_policy_names = optional(object({
      kms_read_write             = optional(string, "KMSReadWriteAccess")
      kms_describe               = optional(string, "KMSDescribeAccess")
      secrets_manager_read       = optional(string, "SecretsManagerReadAccess")
      secrets_manager_describe   = optional(string, "SecretsManagerDescribeAccess")
      secrets_manager_read_write = optional(string, "SecretsManagerReadWriteAccess")
      s3_object_read_write       = optional(string, "S3ObjectReadWriteAccess")
      s3_bucket_list             = optional(string, "S3BucketListAccess")
      ec2_describe               = optional(string, "EC2DescribeAccess")
      ssm_read_write             = optional(string, "SSMReadWriteAccess")
      iam_read                   = optional(string, "IAMReadAccess")
    }), {})
  })
  default = {}

  description = <<-EOT
    IAM role configuration for the Vault Enterprise EC2 instances. The module
    creates one role with several inline policies attached. Defaults reflect the
    module's recommended PascalCase naming; consumer-supplied values are passed
    through verbatim with no transformation.
  EOT

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]+$", var.iam_role.name))
    error_message = "IAM role name must contain only alphanumeric or '+=,.@-_' characters."
  }

  validation {
    condition     = length(var.iam_role.name) >= 1 && length(var.iam_role.name) <= 64
    error_message = "IAM role name must be 1-64 characters."
  }

  validation {
    condition = alltrue([
      for policy_name in values(var.iam_role.inline_policy_names) :
      can(regex("^[A-Za-z0-9+=,.@_-]+$", policy_name))
    ])
    error_message = "IAM inline policy names must contain only alphanumeric or '+=,.@-_' characters."
  }

  validation {
    condition = alltrue([
      for policy_name in values(var.iam_role.inline_policy_names) :
      length(policy_name) >= 1 && length(policy_name) <= 64
    ])
    error_message = "IAM inline policy names must be 1-64 characters."
  }

  validation {
    condition     = startswith(var.iam_role.path, "/") && endswith(var.iam_role.path, "/")
    error_message = "IAM role path must start and end with '/'."
  }

  validation {
    condition     = !can(regex("[[:space:]]", var.iam_role.path))
    error_message = "IAM role path must not contain spaces, tabs, or newlines."
  }

  validation {
    condition     = can(regex("^[[:print:]/]+$", var.iam_role.path))
    error_message = "IAM role path must contain only printable ASCII characters."
  }
}

variable "iam_instance_profile" {
  type = object({
    name = optional(string, "VaultEnterpriseServerInstanceProfile")
    path = optional(string, "/")
  })
  default = {}

  description = <<-EOT
    IAM instance profile configuration for the Vault Enterprise EC2 instances.
    The module creates one instance profile and associates it with the IAM role
    created by this module. Defaults reflect the module's recommended PascalCase
    naming; consumer-supplied values are passed through verbatim with no
    transformation.
  EOT

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]+$", var.iam_instance_profile.name))
    error_message = "IAM instance profile name must contain only alphanumeric or '+=,.@-_' characters."
  }

  validation {
    condition     = length(var.iam_instance_profile.name) >= 1 && length(var.iam_instance_profile.name) <= 64
    error_message = "IAM instance profile name must be 1-64 characters."
  }

  validation {
    condition     = startswith(var.iam_instance_profile.path, "/") && endswith(var.iam_instance_profile.path, "/")
    error_message = "IAM instance profile path must start and end with '/'."
  }

  validation {
    condition     = !can(regex("[[:space:]]", var.iam_instance_profile.path))
    error_message = "IAM instance profile path must not contain spaces, tabs, or newlines."
  }

  validation {
    condition     = can(regex("^[[:print:]/]+$", var.iam_instance_profile.path))
    error_message = "IAM instance profile path must contain only printable ASCII characters."
  }
}

variable "route53_record" {
  type = object({
    subdomain = optional(string, "vault")
  })
  default     = {}
  description = <<-EOT
    Route 53 A record configuration. The record is created in the hosted zone
    supplied via `route53_zone` and points (via alias) at the NLB created by
    this module. The record's fully-qualified name is
    `${subdomain}.${route53_zone.name}`.
  EOT

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.route53_record.subdomain))
    error_message = "route53_record.subdomain must be a valid DNS label (lowercase alphanumeric and hyphens, not starting or ending with a hyphen)."
  }
}

variable "vault" {
  type = object({
    enterprise_version = optional(string, "1.21.4+ent")
    cluster_name       = optional(string, "vault-enterprise")
  })
  default     = {}
  description = "Vault Enterprise product configuration."

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+\\+ent(\\.hsm)?(\\.fips1402)?$", var.vault.enterprise_version))
    error_message = "vault.enterprise_version must be a valid Vault Enterprise release version (e.g., 1.21.4+ent, 1.21.4+ent.hsm, 1.21.4+ent.fips1402)."
  }

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]*$", var.vault.cluster_name))
    error_message = "vault.cluster_name must start with an alphanumeric character and contain only alphanumeric characters, underscores, and hyphens."
  }
}

variable "vault_auth" {
  type = object({
    aws = optional(object({
      role_ttl     = optional(string, "4h")
      role_max_ttl = optional(string, "24h")
    }), {})
    jwt = optional(object({
      role_ttl     = optional(string, "1h")
      role_max_ttl = optional(string, "2h")
    }), {})
  })
  default     = {}
  description = <<-EOT
    TTL configuration for Vault auth method roles. `vault_auth.aws` configures
    Vault's AWS auth method (Vault authenticating callers via AWS IAM identities)
    and is unrelated to the `iam_role` variable, which configures the AWS IAM
    role used by the EC2 instances running Vault.
  EOT
}

variable "vault_pki" {
  type = object({
    mount_path = optional(string, "pki_vault")
    intermediate_ca = optional(object({
      common_name  = optional(string, "Vault Intermediate CA")
      country      = optional(string, "")
      organization = optional(string, "")
      key_type     = optional(string, "rsa")
      key_bits     = optional(number, 2048)
    }), {})
    mount_max_ttl                         = optional(string, "26280h")
    server_role_max_ttl                   = optional(string, "24h")
    server_cert_ttl                       = optional(string, "24h")
    signed_intermediate_wait_timeout_secs = optional(number, 1800)
  })
  default     = {}
  description = "Vault PKI secrets engine configuration."

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.vault_pki.mount_path))
    error_message = "vault_pki.mount_path must contain only alphanumeric characters, underscores, and hyphens."
  }

  validation {
    condition     = contains(["ec", "rsa"], var.vault_pki.intermediate_ca.key_type)
    error_message = "vault_pki.intermediate_ca.key_type must be 'ec' or 'rsa'."
  }

  validation {
    condition     = var.vault_pki.intermediate_ca.key_type != "ec" || contains([224, 256, 384, 521], var.vault_pki.intermediate_ca.key_bits)
    error_message = "vault_pki.intermediate_ca.key_bits for 'ec' must be 224, 256, 384, or 521."
  }

  validation {
    condition     = var.vault_pki.intermediate_ca.key_type != "rsa" || contains([2048, 3072, 4096, 8192], var.vault_pki.intermediate_ca.key_bits)
    error_message = "vault_pki.intermediate_ca.key_bits for 'rsa' must be 2048, 3072, 4096, or 8192."
  }
}

variable "vault_snapshots" {
  type = object({
    interval      = optional(number, 3600)
    retain        = optional(number, 72)
    aws_s3_bucket = optional(string, "vault-enterprise-snapshots")
  })
  default     = {}
  description = <<-EOT
    Vault Raft snapshot configuration. The module creates an S3 bucket for
    snapshot storage; bucket configuration beyond `name` is derived from the
    module's other inputs (KMS key, VPC, etc.) and is not exposed. Note that
    S3 bucket names are globally unique across all AWS accounts; consumers
    deploying multiple instances of this module must override the default.
  EOT

  validation {
    condition     = var.vault_snapshots.interval >= 60
    error_message = "vault_snapshots.interval must be at least 60 seconds."
  }

  validation {
    condition     = var.vault_snapshots.retain >= 1
    error_message = "vault_snapshots.retain must be at least 1."
  }
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
