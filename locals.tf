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

  # gp3 volumes deliver a consistent baseline IOPS performance of 3,000 IOPS,
  # which is included with the price of storage.
  gp3_floor_iops = 3000
  # gp3 volumes deliver a consistent baseline throughput performance of 125 MiB/s,
  # which is included with the price of storage.
  gp3_floor_throughput = 125

  # gp3 includes 3,000 IOPS and 125 MiB/s in the per-GB storage price. These
  # are the minimum provisionable values and they cost $0 extra above storage.
  # A volume at the floor cannot waste money no matter how small the instance is,
  # because there is no above-baseline capacity being billed for.
  root_disk_at_floor = (
    var.compute.root_disk.iops == local.gp3_floor_iops &&
    var.compute.root_disk.throughput == local.gp3_floor_throughput
  )

  raft_data_disk_at_floor = (
    var.compute.raft_data_disk.iops == local.gp3_floor_iops &&
    var.compute.raft_data_disk.throughput == local.gp3_floor_throughput
  )

  audit_disk_at_floor = (
    var.compute.audit_disk.iops == local.gp3_floor_iops &&
    var.compute.audit_disk.throughput == local.gp3_floor_throughput
  )
}
