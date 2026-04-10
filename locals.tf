locals {
  vault_fqdn       = "${var.vault_subdomain}.${var.route53_zone.name}"
  vault_node_count = var.vault_node_count
  azs              = slice(data.aws_availability_zones.available.names, 0, 3)

  # Derived: maximum nodes that can be out during instance refresh while
  # maintaining quorum. floor((n-1)/n * 100) gives:
  #   n=3 →  66%  (1 node out, 2 healthy)
  #   n=5 →  80%  (1 node out, 4 healthy)
  instance_refresh_min_healthy_pct = floor(
    (local.vault_node_count - 1) / local.vault_node_count * 100
  )
  cluster_tag_key       = "vault-cluster"
  cluster_tag_value     = var.project_name
  ebs_device_name       = "/dev/xvdf" # AWS convention for the first additional EBS volume
  ebs_audit_device_name = "/dev/sdg"

  config_vault_service          = file("${path.module}/files/vault.service")
  config_vault_service_override = file("${path.module}/files/vault.service.d-override.conf")

  config_snapshot_json = templatefile("${path.module}/templates/snapshot.json.tftpl", {
    aws_s3_bucket = aws_s3_bucket.vault_snapshots.id
    aws_s3_region = data.aws_region.current.region
    interval      = var.vault_snapshot_interval
    retain        = var.vault_snapshot_retain
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
