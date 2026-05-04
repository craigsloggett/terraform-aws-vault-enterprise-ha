locals {
  # (Optional) Existing VPC Configuration
  vpc = var.vpc.existing != null ? {
    id                 = var.vpc.existing.vpc_id
    cidr               = data.aws_vpc.existing[0].cidr_block
    private_subnet_ids = var.vpc.existing.private_subnet_ids
    public_subnet_ids  = var.vpc.existing.public_subnet_ids
    } : {
    id                 = module.vpc[0].vpc_id
    cidr               = var.vpc.cidr
    private_subnet_ids = module.vpc[0].private_subnets
    public_subnet_ids  = module.vpc[0].public_subnets
  }

  # Derived as maximum nodes that can be out during instance refresh
  # while maintaining quorum.
  #  floor( ( n-1 ) / n * 100 ) gives:
  #   n=3 --> 66% (1 node out, 2 healthy)
  #   n=5 --> 80% (1 node out, 4 healthy)
  instance_refresh_min_healthy_pct = floor(
    (var.vault_enterprise_servers.node_count - 1) / var.vault_enterprise_servers.node_count * 100
  )

  # Environment Configuration
  vault_fqdn = "${var.route53_record.subdomain}.${var.route53_zone.name}"

  # EBS Configuration
  ebs_raft_device_name  = "/dev/xvdf"
  ebs_audit_device_name = "/dev/xvdg"

  # Vault Server Configuration
  config_vault_service          = file("${path.module}/files/vault/vault.service")
  config_vault_service_override = file("${path.module}/files/vault/vault.service.override.conf")
  config_vault_admin_policy     = file("${path.module}/files/policies/admin.hcl")

  config_vault_server_policy = templatefile("${path.module}/templates/policies/vault-server.hcl.tftpl", {
    vault_pki_mount_path = var.vault_pki.mount_path
  })

  config_vault_hcl = templatefile("${path.module}/templates/vault/vault.hcl.tftpl", {
    cluster_name                      = var.vault.cluster_name
    vault_fqdn                        = trimsuffix(aws_route53_record.vault.fqdn, ".")
    aws_region                        = data.aws_region.current.region
    kms_key_alias                     = aws_kms_alias.vault.name
    vault_cluster_auto_join_tag_key   = local.vault_cluster_auto_join_tag_key
    vault_cluster_auto_join_tag_value = local.vault_cluster_auto_join_tag_value
  })

  config_vault_snapshot_json = templatefile("${path.module}/templates/vault/snapshot.json.tftpl", {
    aws_s3_bucket = aws_s3_bucket.vault_snapshots.id
    aws_s3_region = data.aws_region.current.region
    interval      = var.vault_snapshots.interval
    retain        = var.vault_snapshots.retain
  })

  # Cluster Coordination Configuration
  vault_cluster_auto_join_tag_key   = var.vault_enterprise_servers.cluster_auto_join_tag.key
  vault_cluster_auto_join_tag_value = var.vault_enterprise_servers.cluster_auto_join_tag.value

  # Vault Agent Configuration
  config_vault_agent_service                 = file("${path.module}/files/agent/vault-agent.service")
  config_vault_agent_reload_rules            = file("${path.module}/files/agent/vault-agent-reload.rules")
  config_vault_agent_reload_vault_server_tls = file("${path.module}/files/agent/vault-server-tls-reload.sh")

  config_vault_agent_hcl = templatefile("${path.module}/templates/agent/agent.hcl.tftpl", {
    vault_fqdn = trimsuffix(aws_route53_record.vault.fqdn, ".")
  })

  config_vault_agent_server_tls_ctmpl = templatefile("${path.module}/templates/agent/vault-server-tls.ctmpl.tftpl", {
    vault_fqdn                = trimsuffix(aws_route53_record.vault.fqdn, ".")
    vault_pki_mount_path      = var.vault_pki.mount_path
    vault_pki_server_cert_ttl = var.vault_pki.server_cert_ttl
  })

}
