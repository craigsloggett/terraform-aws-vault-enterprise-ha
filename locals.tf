locals {
  vault_fqdn = "${var.vault_subdomain}.${var.route53_zone.name}"
  azs        = slice(data.aws_availability_zones.available.names, 0, 3)

  # Derived as maximum nodes that can be out during instance refresh
  # while maintaining quorum.
  #  floor( ( n-1 ) / n * 100 ) gives:
  #   n=3 →  66%  (1 node out, 2 healthy)
  #   n=5 →  80%  (1 node out, 4 healthy)
  instance_refresh_min_healthy_pct = floor(
    (var.vault_node_count - 1) / var.vault_node_count * 100
  )
  cluster_tag_key       = "vault-cluster"
  cluster_tag_value     = var.project_name
  ebs_raft_device_name  = "/dev/xvdf"
  ebs_audit_device_name = "/dev/xvdg"

  # ---------------------------------------------------------------------------
  # Vault cluster configuration content
  # ---------------------------------------------------------------------------

  config_vault_service          = file("${path.module}/files/config/vault/vault.service")
  config_vault_service_override = file("${path.module}/files/config/vault/vault.service.override.conf")

  config_vault_hcl = templatefile("${path.module}/templates/config/vault/vault.hcl.tftpl", {
    cluster_name      = var.project_name
    vault_fqdn        = trimsuffix(aws_route53_record.vault.fqdn, ".")
    region            = data.aws_region.current.region
    kms_key_alias     = aws_kms_alias.vault.name
    cluster_tag_key   = local.cluster_tag_key
    cluster_tag_value = local.cluster_tag_value
  })

  config_vault_snapshot_json = templatefile("${path.module}/templates/config/vault/snapshot.json.tftpl", {
    aws_s3_bucket = aws_s3_bucket.vault_snapshots.id
    aws_s3_region = data.aws_region.current.region
    interval      = var.vault_snapshot_interval
    retain        = var.vault_snapshot_retain
  })

  # ---------------------------------------------------------------------------
  # Vault Agent configuration content
  # ---------------------------------------------------------------------------

  config_agent_service                 = file("${path.module}/files/config/agent/vault-agent.service")
  config_agent_reload_rules            = file("${path.module}/files/config/agent/vault-agent-reload.rules")
  config_agent_reload_vault_server_tls = file("${path.module}/files/config/agent/vault-server-tls-reload.sh")

  config_agent_hcl = templatefile("${path.module}/templates/config/agent/agent.hcl.tftpl", {
    vault_fqdn = local.vault_fqdn
  })

  config_agent_server_tls_ctmpl = templatefile("${path.module}/templates/config/agent/vault-server-tls.ctmpl.tftpl", {
    vault_fqdn = local.vault_fqdn
  })

  # ---------------------------------------------------------------------------
  # Cloud-init scripts — shared helpers
  # ---------------------------------------------------------------------------

  script_system_logging    = file("${path.module}/files/scripts/system/logging.sh")
  script_aws_imds          = file("${path.module}/files/scripts/aws/imds.sh")
  script_aws_secrets       = file("${path.module}/files/scripts/aws/secrets.sh")
  script_aws_ebs           = file("${path.module}/files/scripts/aws/ebs.sh")
  script_system_packages   = file("${path.module}/files/scripts/system/packages.sh")
  script_system_time       = file("${path.module}/files/scripts/system/time.sh")
  script_vault_user        = file("${path.module}/files/scripts/vault/user.sh")
  script_vault_directories = file("${path.module}/files/scripts/vault/directories.sh")
  script_vault_cli         = file("${path.module}/files/scripts/vault/cli.sh")

  # ---------------------------------------------------------------------------
  # Cloud-init scripts — Vault install and service
  # ---------------------------------------------------------------------------

  script_vault_install = templatefile("${path.module}/templates/scripts/vault/install.sh.tftpl", {
    vault_version = var.vault_version
  })

  script_vault_service = templatefile("${path.module}/templates/scripts/vault/service.sh.tftpl", {
    config_vault_service          = local.config_vault_service
    config_vault_service_override = local.config_vault_service_override
  })

  # ---------------------------------------------------------------------------
  # Cloud-init scripts — Vault configuration
  # ---------------------------------------------------------------------------

  script_vault_license = templatefile("${path.module}/templates/scripts/vault/license.sh.tftpl", {
    vault_license_secret_arn = aws_secretsmanager_secret.vault_license.arn
  })

  script_vault_config = templatefile("${path.module}/templates/scripts/vault/config.sh.tftpl", {
    config_vault_hcl           = local.config_vault_hcl
    config_vault_snapshot_json = local.config_vault_snapshot_json
  })

  script_vault_cluster = templatefile("${path.module}/templates/scripts/vault/cluster.sh.tftpl", {
    cluster_tag_key                = local.cluster_tag_key
    cluster_tag_value              = local.cluster_tag_value
    vault_recovery_keys_secret_arn = aws_secretsmanager_secret.vault_recovery_keys.arn
  })

  script_vault_raft = templatefile("${path.module}/templates/scripts/vault/raft.sh.tftpl", {
    vault_minimum_quorum_size = var.vault_node_count
  })

  script_vault_pki = templatefile("${path.module}/templates/scripts/vault/pki.sh.tftpl", {
    cluster_name           = title(var.project_name)
    vault_pki_organization = var.vault_pki_organization
    vault_pki_country      = var.vault_pki_country
  })

  script_vault_auth = templatefile("${path.module}/templates/scripts/vault/auth.sh.tftpl", {
    vault_iam_role_arn = aws_iam_role.vault.arn
  })

  script_vault_audit = templatefile("${path.module}/templates/scripts/vault/audit.sh.tftpl", {})

  script_vault_tls = templatefile("${path.module}/templates/scripts/vault/tls.sh.tftpl", {
    bootstrap_tls_ca_cert_secret_arn     = aws_secretsmanager_secret.vault_bootstrap_ca_cert.arn
    bootstrap_tls_server_cert_secret_arn = aws_secretsmanager_secret.vault_bootstrap_server_cert.arn
    bootstrap_tls_server_key_secret_arn  = aws_secretsmanager_secret.vault_bootstrap_server_key.arn
  })

  # ---------------------------------------------------------------------------
  # Cloud-init scripts — Vault Agent
  # ---------------------------------------------------------------------------

  script_agent_config = templatefile("${path.module}/templates/scripts/agent/config.sh.tftpl", {
    config_agent_hcl                     = local.config_agent_hcl
    config_agent_server_tls_ctmpl        = local.config_agent_server_tls_ctmpl
    config_agent_reload_vault_server_tls = local.config_agent_reload_vault_server_tls
    config_agent_reload_rules            = local.config_agent_reload_rules
  })

  script_agent_service = templatefile("${path.module}/templates/scripts/agent/service.sh.tftpl", {
    config_agent_service = local.config_agent_service
  })

  vpc = var.existing_vpc != null ? {
    id                 = var.existing_vpc.vpc_id
    cidr               = data.aws_vpc.existing[0].cidr_block
    private_subnet_ids = var.existing_vpc.private_subnet_ids
    public_subnet_ids  = var.existing_vpc.public_subnet_ids
    } : {
    id                 = module.vpc[0].vpc_id
    cidr               = var.vpc_cidr
    private_subnet_ids = module.vpc[0].private_subnets
    public_subnet_ids  = module.vpc[0].public_subnets
  }
}
