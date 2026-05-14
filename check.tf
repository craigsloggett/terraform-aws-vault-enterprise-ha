check "ebs_saturates_instance_baseline" {
  assert {
    condition = (
      local.root_disk_at_floor ||
      var.compute.root_disk.iops >= data.aws_ec2_instance_type.compute.ebs_performance_baseline_iops
    )
    error_message = format(
      "compute.root_disk.iops (%d) is below the %s baseline EBS IOPS (%d). The volume cannot saturate the instance's sustained capacity.",
      var.compute.root_disk.iops,
      var.compute.instance_type,
      data.aws_ec2_instance_type.compute.ebs_performance_baseline_iops,
    )
  }

  assert {
    condition = (
      local.root_disk_at_floor ||
      var.compute.root_disk.throughput >= data.aws_ec2_instance_type.compute.ebs_performance_baseline_throughput
    )
    error_message = format(
      "compute.root_disk.throughput (%d MiB/s) is below the %s baseline EBS throughput (%.1f MiB/s). The volume cannot saturate the instance's sustained capacity.",
      var.compute.root_disk.throughput,
      var.compute.instance_type,
      data.aws_ec2_instance_type.compute.ebs_performance_baseline_throughput,
    )
  }

  assert {
    condition = (
      local.raft_data_disk_at_floor ||
      var.compute.raft_data_disk.iops >= data.aws_ec2_instance_type.compute.ebs_performance_baseline_iops
    )
    error_message = format(
      "compute.raft_data_disk.iops (%d) is below the %s baseline EBS IOPS (%d). The volume cannot saturate the instance's sustained capacity.",
      var.compute.raft_data_disk.iops,
      var.compute.instance_type,
      data.aws_ec2_instance_type.compute.ebs_performance_baseline_iops,
    )
  }

  assert {
    condition = (
      local.raft_data_disk_at_floor ||
      var.compute.raft_data_disk.throughput >= data.aws_ec2_instance_type.compute.ebs_performance_baseline_throughput
    )
    error_message = format(
      "compute.raft_data_disk.throughput (%d MiB/s) is below the %s baseline EBS throughput (%.1f MiB/s). The volume cannot saturate the instance's sustained capacity.",
      var.compute.raft_data_disk.throughput,
      var.compute.instance_type,
      data.aws_ec2_instance_type.compute.ebs_performance_baseline_throughput,
    )
  }

  assert {
    condition = (
      local.audit_disk_at_floor ||
      var.compute.audit_disk.iops >= data.aws_ec2_instance_type.compute.ebs_performance_baseline_iops
    )
    error_message = format(
      "compute.audit_disk.iops (%d) is below the %s baseline EBS IOPS (%d). The volume cannot saturate the instance's sustained capacity.",
      var.compute.audit_disk.iops,
      var.compute.instance_type,
      data.aws_ec2_instance_type.compute.ebs_performance_baseline_iops,
    )
  }

  assert {
    condition = (
      local.audit_disk_at_floor ||
      var.compute.audit_disk.throughput >= data.aws_ec2_instance_type.compute.ebs_performance_baseline_throughput
    )
    error_message = format(
      "compute.audit_disk.throughput (%d MiB/s) is below the %s baseline EBS throughput (%.1f MiB/s). The volume cannot saturate the instance's sustained capacity.",
      var.compute.audit_disk.throughput,
      var.compute.instance_type,
      data.aws_ec2_instance_type.compute.ebs_performance_baseline_throughput,
    )
  }
}
