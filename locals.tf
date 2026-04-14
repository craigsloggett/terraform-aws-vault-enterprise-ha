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

  config_vault_service          = file("${path.module}/files/vault/vault.service")
  config_vault_service_override = file("${path.module}/files/vault/vault.service.override.conf")

  config_vault_hcl = templatefile("${path.module}/templates/vault/vault.hcl.tftpl", {
    cluster_name      = var.project_name
    vault_fqdn        = trimsuffix(aws_route53_record.vault.fqdn, ".")
    aws_region        = data.aws_region.current.region
    kms_key_alias     = aws_kms_alias.vault.name
    cluster_tag_key   = local.cluster_tag_key
    cluster_tag_value = local.cluster_tag_value
  })

  config_vault_snapshot_json = templatefile("${path.module}/templates/vault/snapshot.json.tftpl", {
    aws_s3_bucket = aws_s3_bucket.vault_snapshots.id
    aws_s3_region = data.aws_region.current.region
    interval      = var.vault_snapshot_interval
    retain        = var.vault_snapshot_retain
  })

  # ---------------------------------------------------------------------------
  # Vault Agent configuration content
  # ---------------------------------------------------------------------------

  config_agent_service                 = file("${path.module}/files/agent/vault-agent.service")
  config_agent_reload_rules            = file("${path.module}/files/agent/vault-agent-reload.rules")
  config_agent_reload_vault_server_tls = file("${path.module}/files/agent/vault-server-tls-reload.sh")
  config_agent_hcl                     = file("${path.module}/files/agent/agent.hcl")
  config_agent_server_tls_ctmpl        = file("${path.module}/files/agent/vault-server-tls.ctmpl")

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
