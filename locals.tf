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

  config_vault_service                 = file("${path.module}/files/config/vault/vault.service")
  config_vault_service_override        = file("${path.module}/files/config/vault/vault.service.d-override.conf")
  config_agent_service                 = file("${path.module}/files/config/agent/vault-agent.service")
  config_agent_reload_rules            = file("${path.module}/files/config/agent/10-vault-agent-reload.rules")
  config_agent_reload_vault_server_tls = file("${path.module}/files/config/agent/reload-vault-server-tls")

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

  config_agent_hcl = templatefile("${path.module}/templates/config/agent/agent.hcl.tftpl", {
    vault_fqdn = local.vault_fqdn
  })

  config_agent_server_tls_ctmpl = templatefile("${path.module}/templates/config/agent/vault-server-tls.ctmpl.tftpl", {
    vault_fqdn = local.vault_fqdn
  })

  # Cloud-init script fragments — pure shell (no Terraform interpolation)
  script_logging                 = file("${path.module}/files/scripts/logging.sh")
  script_ec2_metadata_helpers    = file("${path.module}/files/scripts/ec2-metadata-helpers.sh")
  script_secrets_manager_helpers = file("${path.module}/files/scripts/secrets-manager-helpers.sh")
  script_ebs_helpers             = file("${path.module}/files/scripts/ebs-helpers.sh")
  script_system_setup            = file("${path.module}/files/scripts/system-setup.sh")
  # Vault scripts — pure shell
  script_vault_write_system        = file("${path.module}/files/scripts/vault/write-system.sh")
  script_vault_write_license       = file("${path.module}/files/scripts/vault/write-license.sh")
  script_vault_write_tls_materials = file("${path.module}/files/scripts/vault/write-tls-materials.sh")
  script_vault_configure_tls       = file("${path.module}/files/scripts/vault/configure-tls.sh")
  script_vault_configure_aws_auth  = file("${path.module}/files/scripts/vault/configure-aws-auth.sh")
  script_vault_configure_audit     = file("${path.module}/files/scripts/vault/configure-audit.sh")
  script_vault_configure_snapshots = file("${path.module}/files/scripts/vault/configure-snapshots.sh")
  script_vault_write_cli_config    = file("${path.module}/files/scripts/vault/write-cli-config.sh")

  # Vault scripts — need Terraform interpolation
  script_vault_install = templatefile("${path.module}/templates/scripts/vault/install.sh.tftpl", {
    vault_version = var.vault_version
  })

  script_vault_get_license = templatefile("${path.module}/templates/scripts/vault/get-license.sh.tftpl", {
    vault_license_secret_arn = aws_secretsmanager_secret.vault_license.arn
  })

  script_vault_get_bootstrap_tls_materials = templatefile("${path.module}/templates/scripts/vault/get-bootstrap-tls-materials.sh.tftpl", {
    bootstrap_tls_ca_cert_secret_arn     = aws_secretsmanager_secret.vault_bootstrap_ca_cert.arn
    bootstrap_tls_server_cert_secret_arn = aws_secretsmanager_secret.vault_bootstrap_server_cert.arn
    bootstrap_tls_server_key_secret_arn  = aws_secretsmanager_secret.vault_bootstrap_server_key.arn
  })

  script_vault_write_systemd_unit = templatefile("${path.module}/templates/scripts/vault/write-systemd-unit.sh.tftpl", {
    config_vault_service          = local.config_vault_service
    config_vault_service_override = local.config_vault_service_override
  })

  script_vault_write_config = templatefile("${path.module}/templates/scripts/vault/write-config.sh.tftpl", {
    config_vault_hcl = local.config_vault_hcl
  })

  script_vault_write_snapshot_config = templatefile("${path.module}/templates/scripts/vault/write-snapshot-config.sh.tftpl", {
    config_vault_snapshot_json = local.config_vault_snapshot_json
  })

  script_vault_configure_autopilot = templatefile("${path.module}/templates/scripts/vault/configure-autopilot.sh.tftpl", {
    vault_minimum_quorum_size = var.vault_node_count
  })

  script_vault_initialize_cluster = templatefile("${path.module}/templates/scripts/vault/initialize-cluster.sh.tftpl", {
    cluster_tag_key                = local.cluster_tag_key
    cluster_tag_value              = local.cluster_tag_value
    vault_recovery_keys_secret_arn = aws_secretsmanager_secret.vault_recovery_keys.arn
  })

  script_vault_configure_pki = templatefile("${path.module}/templates/scripts/vault/configure-pki.sh.tftpl", {
    cluster_name           = title(var.project_name)
    vault_pki_organization = var.vault_pki_organization
    vault_pki_country      = var.vault_pki_country
  })

  script_vault_configure_server_role = templatefile("${path.module}/templates/scripts/vault/configure-server-role.sh.tftpl", {
    vault_iam_role_arn = aws_iam_role.vault.arn
  })

  # Agent scripts — need Terraform interpolation
  script_agent_write_config = templatefile("${path.module}/templates/scripts/agent/write-config.sh.tftpl", {
    config_agent_hcl = local.config_agent_hcl
  })

  script_agent_write_tls_template = templatefile("${path.module}/templates/scripts/agent/write-tls-template.sh.tftpl", {
    config_agent_server_tls_ctmpl = local.config_agent_server_tls_ctmpl
  })

  script_agent_write_reload_script = templatefile("${path.module}/templates/scripts/agent/write-reload-script.sh.tftpl", {
    config_agent_reload_vault_server_tls = local.config_agent_reload_vault_server_tls
  })

  script_agent_write_polkit_rules = templatefile("${path.module}/templates/scripts/agent/write-polkit-rules.sh.tftpl", {
    config_agent_reload_rules = local.config_agent_reload_rules
  })

  script_agent_write_systemd_unit = templatefile("${path.module}/templates/scripts/agent/write-systemd-unit.sh.tftpl", {
    config_agent_service = local.config_agent_service
  })

  # Agent scripts — pure shell
  script_agent_start = file("${path.module}/files/scripts/agent/start.sh")

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
