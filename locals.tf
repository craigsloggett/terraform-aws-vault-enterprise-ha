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

  config_vault_service            = file("${path.module}/files/vault.service")
  config_vault_service_override   = file("${path.module}/files/vault.service.d-override.conf")
  config_vault_agent_service      = file("${path.module}/files/vault-agent.service")
  config_vault_agent_reload_rules = file("${path.module}/files/10-vault-agent-reload.rules")
  config_reload_vault_server_tls  = file("${path.module}/files/reload-vault-server-tls")

  config_agent_hcl = templatefile("${path.module}/templates/agent.hcl.tftpl", {
    vault_fqdn = local.vault_fqdn
  })

  config_vault_server_tls_ctmpl = templatefile("${path.module}/templates/vault-server-tls.ctmpl.tftpl", {
    vault_fqdn = local.vault_fqdn
  })

  config_vault_hcl = templatefile("${path.module}/templates/vault.hcl.tftpl", {
    cluster_name      = var.project_name
    vault_fqdn        = trimsuffix(aws_route53_record.vault.fqdn, ".")
    region            = data.aws_region.current.region
    kms_key_alias     = aws_kms_alias.vault.name
    cluster_tag_key   = local.cluster_tag_key
    cluster_tag_value = local.cluster_tag_value
  })

  config_snapshot_json = templatefile("${path.module}/templates/snapshot.json.tftpl", {
    aws_s3_bucket = aws_s3_bucket.vault_snapshots.id
    aws_s3_region = data.aws_region.current.region
    interval      = var.vault_snapshot_interval
    retain        = var.vault_snapshot_retain
  })

  # Cloud-init script fragments — pure shell (no Terraform interpolation)
  script_logging       = file("${path.module}/files/scripts/logging.sh")
  script_aws_helpers   = file("${path.module}/files/scripts/aws-helpers.sh")
  script_system_setup  = file("${path.module}/files/scripts/system-setup.sh")
  script_vault_system  = file("${path.module}/files/scripts/vault-system.sh")
  script_vault_install = file("${path.module}/files/scripts/vault-install.sh")
  script_vault_cluster = file("${path.module}/files/scripts/vault-cluster.sh")
  script_vault_pki     = file("${path.module}/files/scripts/vault-pki.sh")
  script_vault_auth    = file("${path.module}/files/scripts/vault-auth.sh")
  script_vault_tls     = file("${path.module}/files/scripts/vault-tls.sh")
  script_vault_cli     = file("${path.module}/files/scripts/vault-cli.sh")

  # Cloud-init script fragment — needs Terraform interpolation for config content
  script_vault_config_files = templatefile("${path.module}/templates/scripts/vault-config-files.sh.tftpl", {
    config_vault_service            = local.config_vault_service
    config_vault_service_override   = local.config_vault_service_override
    config_vault_hcl                = local.config_vault_hcl
    config_snapshot_json            = local.config_snapshot_json
    config_agent_hcl                = local.config_agent_hcl
    config_vault_server_tls_ctmpl   = local.config_vault_server_tls_ctmpl
    config_reload_vault_server_tls  = local.config_reload_vault_server_tls
    config_vault_agent_reload_rules = local.config_vault_agent_reload_rules
    config_vault_agent_service      = local.config_vault_agent_service
    vault_minimum_quorum_size       = var.vault_node_count
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
