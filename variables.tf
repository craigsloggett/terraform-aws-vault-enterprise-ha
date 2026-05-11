# Required

variable "vault_enterprise_license" {
  type        = string
  description = "Vault Enterprise license string."
  sensitive   = true
}

variable "route53_zone" {
  type = object({
    zone_id = string
    name    = string
  })

  description = "Route 53 hosted zone for the Vault DNS record. Accepts the result of an `aws_route53_zone` data source directly."
}

# Optional

variable "vault" {
  type = object({
    version       = optional(string, "1.21.4+ent")
    ui            = optional(bool, true)
    disable_mlock = optional(bool, true)
    cluster_name  = optional(string, "vault-enterprise")

    log_level  = optional(string, "info")
    log_format = optional(string, "json")

    listener_tcp = optional(object({
      tls_min_version = optional(string, "tls13")
    }), {})

    telemetry = optional(object({
      prometheus_retention_time = optional(string, "24h")
      disable_hostname          = optional(bool, true)
    }), {})

    secretsmanager_secret = optional(object({
      license_name_prefix       = optional(string, "vault-enterprise-license-")
      recovery_keys_name_prefix = optional(string, "vault-enterprise-recovery-keys-")
      root_token_name_prefix    = optional(string, "vault-enterprise-root-token-")
    }), {})
  })

  default     = {}
  description = "Vault Enterprise product configuration."

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+\\+ent(\\.hsm)?(\\.fips1402)?$", var.vault.version))
    error_message = "vault.version must be a valid Vault Enterprise release version (e.g., 1.21.4+ent, 1.21.4+ent.hsm, 1.21.4+ent.fips1402)."
  }

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]*$", var.vault.cluster_name))
    error_message = "vault.cluster_name must start with an alphanumeric character and contain only alphanumeric characters, underscores, and hyphens."
  }
}

variable "vault_autopilot" {
  type = object({
    cleanup_dead_servers               = optional(bool, true)
    dead_server_last_contact_threshold = optional(string, "24h")
  })

  default     = {}
  description = "Vault Enterprise autopilot configuration."

  validation {
    condition     = can(timeadd("2000-01-01T00:00:00Z", var.vault_autopilot.dead_server_last_contact_threshold))
    error_message = "vault_autopilot.dead_server_last_contact_threshold must be a Go duration string (e.g., \"24h\", \"1h30m\"). Valid Units: \"s\", \"m\", \"h\"."
  }
}

variable "vault_snapshot" {
  type = object({
    aws_s3_bucket = optional(object({
      name_prefix   = optional(string, "vault-enterprise-snapshots-")
      force_destroy = optional(bool, false)
    }), {})
    path_prefix = optional(string, "snapshots/")
    file_prefix = optional(string, "vault-snapshot")
    interval    = optional(number, 3600)
    retain      = optional(number, 72)
  })

  default     = {}
  description = "Vault Enterprise snapshot configuration."

  validation {
    condition     = var.vault_snapshot.interval >= 60
    error_message = "vault_snapshot.interval must be at least 60 seconds."
  }

  validation {
    condition     = var.vault_snapshot.retain >= 1
    error_message = "vault_snapshot.retain must be at least 1."
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
    TTL configuration for Vault auth method roles.
  EOT
}

variable "vault_auth_jwt_hcp_terraform" {
  type = object({
    hostname              = optional(string, "app.terraform.io")
    organization_name     = optional(string, "")
    workspace_id          = optional(string, "")
    oidc_discovery_ca_pem = optional(string, "")
    mount_path            = optional(string, "app-terraform-io")
    role_name             = optional(string, "hcp-terraform")
  })

  default     = {}
  description = <<-EOT
    Configuration for the HCP Terraform JWT auth method that provides
    dynamic, short-lived Vault credentials to HCP Terraform workspaces.
    When `organization_name` and `workspace_id` are set, a JWT auth method
    is mounted at `mount_path` in the root namespace and configured to
    verify tokens against `hostname` via OIDC discovery. A role named
    `role_name` is created against that mount with `bound_claims`
    restricting authentication to the declared organization and workspace.
  EOT
}

variable "vault_pki" {
  type = object({
    mount_path                                = optional(string, "pki_vault")
    mount_max_ttl                             = optional(string, "26280h")
    server_role_max_ttl                       = optional(string, "24h")
    server_cert_ttl                           = optional(string, "24h")
    signed_intermediate_poll_interval_seconds = optional(number, 10)
    signed_intermediate_wait_timeout_seconds  = optional(number, 1800)

    secretsmanager_secret = optional(object({
      signed_intermediate_ca_name_prefix = optional(string, "vault-enterprise-signed-intermediate-ca-")
    }), {})

    ssm_parameter = optional(object({
      intermediate_ca_name     = optional(string, "/vault-enterprise/pki/intermediate-ca")
      intermediate_ca_csr_name = optional(string, "/vault-enterprise/pki/intermediate-ca-csr")
    }), {})

    intermediate_ca = optional(object({
      common_name  = optional(string, "Vault Intermediate CA")
      country      = optional(string, "")
      organization = optional(string, "")
      key_type     = optional(string, "ec")
      key_bits     = optional(number, 384)
    }), {})
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

  validation {
    condition     = can(timeadd("2000-01-01T00:00:00Z", var.vault_pki.mount_max_ttl))
    error_message = "vault_pki.mount_max_ttl must be a Go duration string (e.g., \"24h\", \"1h30m\"). Valid Units: \"s\", \"m\", \"h\"."
  }

  validation {
    condition     = can(timeadd("2000-01-01T00:00:00Z", var.vault_pki.server_role_max_ttl))
    error_message = "vault_pki.server_role_max_ttl must be a Go duration string (e.g., \"24h\", \"1h30m\"). Valid Units: \"s\", \"m\", \"h\"."
  }

  validation {
    condition     = can(timeadd("2000-01-01T00:00:00Z", var.vault_pki.server_cert_ttl))
    error_message = "vault_pki.server_cert_ttl must be a Go duration string (e.g., \"24h\", \"1h30m\"). Valid Units: \"s\", \"m\", \"h\"."
  }
}

variable "ami" {
  type = object({
    owners = optional(list(string), ["amazon"])
    name   = optional(string, "ubuntu/images/hvm-ssd-gp3/ubuntu-resolute-26.04-amd64-server-20260503")
  })

  default     = {}
  description = "AMI for EC2 instances. Must be Ubuntu or Debian-based. Accepts the result of an `aws_ami` data source directly."
}

variable "key_pair" {
  type = object({
    key_name = string
  })

  default     = null
  description = "EC2 key pair for SSH access. Accepts the result of an `aws_key_pair` data source directly."
}

variable "vpc" {
  type = object({
    name            = optional(string, "vault-enterprise-vpc")
    cidr            = optional(string, "10.0.0.0/16")
    private_subnets = optional(list(string), ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"])
    public_subnets  = optional(list(string), ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"])

    endpoints = optional(object({
      secretsmanager_name = optional(string, "vault-enterprise-secretsmanager-vpc-endpoint")
      kms_name            = optional(string, "vault-enterprise-kms-vpc-endpoint")
      ec2_name            = optional(string, "vault-enterprise-ec2-vpc-endpoint")
      s3_name             = optional(string, "vault-enterprise-s3-vpc-endpoint")

      security_group = optional(object({
        name_prefix = optional(string, "vault-enterprise-vpc-endpoints-")
        name        = optional(string, "vault-enterprise-vpc-endpoints")
      }), {})
    }), {})

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
    set, those creation fields are ignored and the supplied VPC is used. The
    supplied VPC must have the required VPC endpoints configured.
  EOT

  validation {
    condition     = var.vpc.existing == null || (length(var.vpc.existing.private_subnet_ids) > 0 && length(var.vpc.existing.public_subnet_ids) > 0)
    error_message = "vpc.existing subnet ID lists must be non-empty when existing is set."
  }
}

variable "bastion" {
  type = object({
    name          = optional(string, "vault-enterprise-bastion-host")
    volume_name   = optional(string, "vault-enterprise-bastion-host-volume")
    instance_type = optional(string, "t3.micro")
    allowed_cidrs = optional(list(string), ["0.0.0.0/0"])

    security_group = optional(object({
      name_prefix = optional(string, "vault-enterprise-bastion-host-")
      name        = optional(string, "vault-enterprise-bastion-host")
    }), {})
  })

  default     = {}
  description = <<-EOT
    Bastion host configuration. `allowed_cidrs` defaults to `["0.0.0.0/0"]` for
    convenience; restrict to known ranges in any production deployment.
  EOT

  validation {
    condition     = alltrue([for cidr in var.bastion.allowed_cidrs : can(cidrhost(cidr, 0))])
    error_message = "bastion.allowed_cidrs entries must be valid CIDR blocks."
  }
}

variable "compute" {
  type = object({
    instance_type = optional(string, "m6a.2xlarge")
    node_count    = optional(number, 5)

    root_disk = optional(object({
      volume_size = optional(number, 50)
      iops        = optional(number, 3000)
      throughput  = optional(number, 125)
    }), {})

    raft_data_disk = optional(object({
      volume_size = optional(number, 50)
      iops        = optional(number, 12000)
      throughput  = optional(number, 312)
    }), {})

    audit_disk = optional(object({
      volume_size = optional(number, 50)
      iops        = optional(number, 12000)
      throughput  = optional(number, 312)
    }), {})

    auto_join = optional(object({
      tag_key   = optional(string, "vault:raft:retryjoin:autojoin")
      tag_value = optional(string, "vault-enterprise")
    }), {})

    security_group = optional(object({
      name_prefix = optional(string, "vault-enterprise-servers-")
      name        = optional(string, "vault-enterprise-servers")
    }), {})

    launch_template = optional(object({
      name_prefix = optional(string, "vault-enterprise-servers-")
      volume_name = optional(string, "vault-enterprise-volume")
    }), {})

    autoscaling_group = optional(object({
      name_prefix   = optional(string, "vault-enterprise-servers-")
      instance_name = optional(string, "vault-enterprise-server")
    }), {})
  })

  default     = {}
  description = "Configuration for the Vault Enterprise server EC2 instances and their EBS volumes."

  validation {
    condition     = contains([3, 5], var.compute.node_count)
    error_message = "compute.node_count must be 3 or 5 for Raft quorum."
  }

  validation {
    condition     = length(var.compute.auto_join.tag_value) > 0
    error_message = "compute.auto_join.tag_value must be a non-empty string to prevent accidentally joining an existing cluster."
  }

  validation {
    condition     = var.compute.root_disk.volume_size >= 20 && var.compute.root_disk.volume_size <= 65536
    error_message = "compute.root_disk.volume_size must be between 20 and 65536 GiB."
  }

  validation {
    condition     = var.compute.root_disk.iops >= 3000 && var.compute.root_disk.iops <= 80000
    error_message = "compute.root_disk.iops must be between 3000 and 80000."
  }

  validation {
    condition     = var.compute.root_disk.throughput >= 125 && var.compute.root_disk.throughput <= 2000
    error_message = "compute.root_disk.throughput must be between 125 and 2000 MiB/s."
  }

  validation {
    condition     = var.compute.root_disk.iops <= var.compute.root_disk.volume_size * 500
    error_message = "compute.root_disk.iops cannot exceed compute.root_disk.volume_size * 500."
  }

  validation {
    condition     = var.compute.root_disk.throughput <= var.compute.root_disk.iops * 0.25
    error_message = "compute.root_disk.throughput cannot exceed compute.root_disk.iops * 0.25."
  }

  validation {
    condition     = var.compute.raft_data_disk.volume_size >= 1 && var.compute.raft_data_disk.volume_size <= 65536
    error_message = "compute.raft_data_disk.volume_size must be between 1 and 65536 GiB."
  }

  validation {
    condition     = var.compute.raft_data_disk.iops >= 3000 && var.compute.raft_data_disk.iops <= 80000
    error_message = "compute.raft_data_disk.iops must be between 3000 and 80000."
  }

  validation {
    condition     = var.compute.raft_data_disk.throughput >= 125 && var.compute.raft_data_disk.throughput <= 2000
    error_message = "compute.raft_data_disk.throughput must be between 125 and 2000 MiB/s."
  }

  validation {
    condition     = var.compute.raft_data_disk.iops <= var.compute.raft_data_disk.volume_size * 500
    error_message = "compute.raft_data_disk.iops cannot exceed compute.raft_data_disk.volume_size * 500."
  }

  validation {
    condition     = var.compute.raft_data_disk.throughput <= var.compute.raft_data_disk.iops * 0.25
    error_message = "compute.raft_data_disk.throughput cannot exceed compute.raft_data_disk.iops * 0.25."
  }

  validation {
    condition     = var.compute.audit_disk.volume_size >= 1 && var.compute.audit_disk.volume_size <= 65536
    error_message = "compute.audit_disk.volume_size must be between 1 and 65536 GiB."
  }

  validation {
    condition     = var.compute.audit_disk.iops >= 3000 && var.compute.audit_disk.iops <= 80000
    error_message = "compute.audit_disk.iops must be between 3000 and 80000."
  }

  validation {
    condition     = var.compute.audit_disk.throughput >= 125 && var.compute.audit_disk.throughput <= 2000
    error_message = "compute.audit_disk.throughput must be between 125 and 2000 MiB/s."
  }

  validation {
    condition     = var.compute.audit_disk.iops <= var.compute.audit_disk.volume_size * 500
    error_message = "compute.audit_disk.iops cannot exceed compute.audit_disk.volume_size * 500."
  }

  validation {
    condition     = var.compute.audit_disk.throughput <= var.compute.audit_disk.iops * 0.25
    error_message = "compute.audit_disk.throughput cannot exceed compute.audit_disk.iops * 0.25."
  }
}

variable "nlb" {
  type = object({
    name_prefix       = optional(string, "vault-")
    internal          = optional(bool, true)
    api_allowed_cidrs = optional(list(string), [])

    lb_target_group = optional(object({
      name_prefix = optional(string, "vault-")
    }), {})
  })

  default     = {}
  description = <<-EOT
    NLB configuration for the Vault API. `api_allowed_cidrs` is only effective
    when `internal` is `false`.
  EOT

  validation {
    condition     = length(var.nlb.name_prefix) <= 6
    error_message = "nlb.name_prefix must be 6 characters or fewer."
  }

  validation {
    condition     = length(var.nlb.lb_target_group.name_prefix) <= 6
    error_message = "nlb.lb_target_group.name_prefix must be 6 characters or fewer."
  }

  validation {
    condition     = alltrue([for cidr in var.nlb.api_allowed_cidrs : can(cidrhost(cidr, 0))])
    error_message = "nlb.api_allowed_cidrs entries must be valid CIDR blocks."
  }
}

variable "kms_key" {
  type = object({
    name                    = optional(string, "vault-enterprise-auto-unseal-key")
    alias                   = optional(string, "vault-enterprise-auto-unseal-key")
    deletion_window_in_days = optional(number, 7)
    enable_key_rotation     = optional(bool, true)
  })

  default     = {}
  description = "Configuration for the KMS key used for Vault auto-unseal."

  validation {
    condition     = var.kms_key.deletion_window_in_days >= 7 && var.kms_key.deletion_window_in_days <= 30
    error_message = "kms_key.deletion_window_in_days must be between 7 and 30."
  }
}

variable "iam_role" {
  type = object({
    name = optional(string, "VaultEnterpriseServerRole")
    path = optional(string, "/")

    instance_profile = optional(object({
      name = optional(string, "VaultEnterpriseServerInstanceProfile")
      path = optional(string, "/")
    }), {})

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

  default     = {}
  description = <<-EOT
    IAM role configuration for the Vault Enterprise EC2 instances. The module
    creates one role with several inline policies attached and an associated
    instance profile.
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
  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]+$", var.iam_role.instance_profile.name))
    error_message = "IAM instance profile name must contain only alphanumeric or '+=,.@-_' characters."
  }

  validation {
    condition     = length(var.iam_role.instance_profile.name) >= 1 && length(var.iam_role.instance_profile.name) <= 64
    error_message = "IAM instance profile name must be 1-64 characters."
  }

  validation {
    condition     = startswith(var.iam_role.instance_profile.path, "/") && endswith(var.iam_role.instance_profile.path, "/")
    error_message = "IAM instance profile path must start and end with '/'."
  }

  validation {
    condition     = !can(regex("[[:space:]]", var.iam_role.instance_profile.path))
    error_message = "IAM instance profile path must not contain spaces, tabs, or newlines."
  }

  validation {
    condition     = can(regex("^[[:print:]/]+$", var.iam_role.instance_profile.path))
    error_message = "IAM instance profile path must contain only printable ASCII characters."
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
}

variable "route53_record" {
  type = object({
    subdomain = optional(string, "vault")
  })

  default     = {}
  description = <<-EOT
    Route53 A record configuration. The record is created in the hosted zone
    supplied via `route53_zone` and points (via alias) at the NLB created by
    this module.
  EOT

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.route53_record.subdomain))
    error_message = "route53_record.subdomain must be a valid DNS label (lowercase alphanumeric and hyphens, not starting or ending with a hyphen)."
  }
}

variable "bootstrap" {
  type = object({
    ssm_parameter = optional(object({
      cluster_state_name = optional(string, "/vault-enterprise/bootstrap/cluster/state")
      pki_state_name     = optional(string, "/vault-enterprise/bootstrap/pki/state")
      node_id_name       = optional(string, "/vault-enterprise/bootstrap/node/id")
    }), {})
  })

  default     = {}
  description = <<-EOT
    AWS resources used only during the Vault bootstrap ceremony. SSM parameters
    hold non-sensitive coordination state and the intermediate CA CSR exchanged
    out-of-band.
  EOT
}
