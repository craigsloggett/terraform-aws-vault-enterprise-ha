locals {
  # VPC Configuration
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
  #  floor( ( n-1 ) * 100 / n ) gives:
  #   n=3 --> 66% (1 node out, 2 healthy)
  #   n=5 --> 80% (1 node out, 4 healthy)
  instance_refresh_min_healthy_pct = floor(
    (var.compute.node_count - 1) * 100 / var.compute.node_count
  )

  # Environment Configuration
  vault_fqdn = trimsuffix(aws_route53_record.vault_enterprise.fqdn, ".")
}
