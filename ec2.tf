# Bastion Host

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.selected.id
  instance_type               = var.bastion.instance_type
  key_name                    = var.key_pair.key_name
  subnet_id                   = local.vpc.public_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = var.bastion.name
  }

  volume_tags = {
    Name = var.bastion.volume_name
  }
}

# Vault Nodes

resource "aws_launch_template" "vault_enterprise" {
  name_prefix   = var.compute.launch_template.name_prefix
  image_id      = data.aws_ami.selected.id
  instance_type = var.compute.instance_type
  key_name      = var.key_pair.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.vault_enterprise.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.vault_enterprise_servers.id]
    delete_on_termination       = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64gzip(templatefile("${path.module}/templates/cloud-init.yml.tftpl", {
    bootstrap_env_file = templatefile("${path.module}/templates/bootstrap.env.tftpl", {
      # Environment
      vault_fqdn    = var.vault_fqdn
      vault_version = var.vault.version

      # Auto-join Discovery
      auto_join_tag_key   = var.compute.auto_join.tag_key
      auto_join_tag_value = var.compute.auto_join.tag_value

      # Bootstrap Coordination
      bootstrap_vault_cluster_state_ssm_parameter_name = aws_ssm_parameter.bootstrap_vault_cluster_state.name
      bootstrap_vault_pki_state_ssm_parameter_name     = aws_ssm_parameter.bootstrap_vault_pki_state.name
      bootstrap_instance_id_ssm_parameter_name         = aws_ssm_parameter.bootstrap_instance_id.name

      # Bootstrap Secrets
      license_secret_arn       = aws_secretsmanager_secret.license.arn
      recovery_keys_secret_arn = aws_secretsmanager_secret.recovery_keys.arn
      root_token_secret_arn    = aws_secretsmanager_secret.root_token.arn

      # EBS Storage
      ebs_audit_device_name = "/dev/xvdg"
      ebs_raft_device_name  = "/dev/xvdf"

      # Vault Autopilot
      vault_autopilot_cleanup_dead_servers               = var.vault_autopilot.cleanup_dead_servers
      vault_autopilot_dead_server_last_contact_threshold = var.vault_autopilot.dead_server_last_contact_threshold
      vault_autopilot_min_quorum                         = max(3, floor(var.compute.node_count / 2) + 1)

      # Vault AWS Auth
      vault_aws_auth_role_max_ttl = var.vault_auth.aws.role_max_ttl
      vault_aws_auth_role_ttl     = var.vault_auth.aws.role_ttl
      vault_iam_role_arn          = aws_iam_role.vault_enterprise.arn

      # Vault HCP Terraform JWT Auth
      vault_auth_jwt_hcp_terraform_hostname              = var.vault_auth_jwt_hcp_terraform.hostname
      vault_auth_jwt_hcp_terraform_mount_path            = var.vault_auth_jwt_hcp_terraform.mount_path
      vault_auth_jwt_hcp_terraform_oidc_discovery_ca_pem = var.vault_auth_jwt_hcp_terraform.oidc_discovery_ca_pem
      vault_auth_jwt_hcp_terraform_organization_name     = var.vault_auth_jwt_hcp_terraform.organization_name
      vault_auth_jwt_hcp_terraform_role_name             = var.vault_auth_jwt_hcp_terraform.role_name
      vault_auth_jwt_hcp_terraform_workspace_id          = var.vault_auth_jwt_hcp_terraform.workspace_id
      vault_auth_jwt_role_max_ttl                        = var.vault_auth.jwt.role_max_ttl
      vault_auth_jwt_role_ttl                            = var.vault_auth.jwt.role_ttl

      # Vault PKI
      vault_pki_intermediate_ca_common_name               = var.vault_pki.intermediate_ca.common_name
      vault_pki_intermediate_ca_country                   = var.vault_pki.intermediate_ca.country
      vault_pki_intermediate_ca_csr_ssm_parameter_name    = aws_ssm_parameter.vault_pki_intermediate_ca_csr.name
      vault_pki_intermediate_ca_key_bits                  = var.vault_pki.intermediate_ca.key_bits
      vault_pki_intermediate_ca_key_type                  = var.vault_pki.intermediate_ca.key_type
      vault_pki_intermediate_ca_organization              = var.vault_pki.intermediate_ca.organization
      vault_pki_ca_chain_ssm_parameter_name               = aws_ssm_parameter.vault_pki_ca_chain.name
      vault_pki_mount_path                                = var.vault_pki.mount_path
      vault_pki_server_cert_ttl                           = var.vault_pki.server_cert_ttl
      vault_pki_signed_intermediate_ca_secret_arn         = aws_secretsmanager_secret.vault_pki_signed_intermediate_ca.arn
      vault_pki_signed_intermediate_poll_interval_seconds = var.vault_pki.signed_intermediate_poll_interval_seconds
      vault_pki_signed_intermediate_wait_timeout_seconds  = var.vault_pki.signed_intermediate_wait_timeout_seconds
      vault_pki_vault_mount_max_ttl                       = var.vault_pki.mount_max_ttl
      vault_pki_vault_server_role_max_ttl                 = var.vault_pki.server_role_max_ttl
    })

    # Bootstrap Scripts
    script_common_functions                    = file("${path.module}/files/bootstrap/common-functions.sh")
    script_determine_vault_node_role           = file("${path.module}/files/bootstrap/determine-vault-node-role.sh")
    script_install_vault                       = file("${path.module}/files/bootstrap/install-vault.sh")
    script_write_vault_license                 = file("${path.module}/files/bootstrap/write-vault-license.sh")
    script_write_vault_bootstrap_tls_materials = file("${path.module}/files/bootstrap/write-vault-bootstrap-tls-materials.sh")
    script_prepare_vault_storage               = file("${path.module}/files/bootstrap/prepare-vault-storage.sh")
    script_start_vault                         = file("${path.module}/files/bootstrap/start-vault.sh")
    script_initialize_vault_cluster            = file("${path.module}/files/bootstrap/initialize-vault-cluster.sh")
    script_wait_for_vault_cluster              = file("${path.module}/files/bootstrap/wait-for-vault-cluster.sh")
    script_configure_vault_audit               = file("${path.module}/files/bootstrap/configure-vault-audit.sh")
    script_configure_snapshots                 = file("${path.module}/files/bootstrap/configure-snapshots.sh")
    script_configure_autopilot                 = file("${path.module}/files/bootstrap/configure-autopilot.sh")
    script_configure_vault_aws_auth            = file("${path.module}/files/bootstrap/configure-vault-aws-auth.sh")
    script_configure_vault_jwt_auth            = file("${path.module}/files/bootstrap/configure-vault-jwt-auth.sh")
    script_configure_vault_pki                 = file("${path.module}/files/bootstrap/configure-vault-pki.sh")
    script_issue_vault_tls_cert                = file("${path.module}/files/bootstrap/issue-vault-tls-cert.sh")

    # Bootstrap TLS Materials
    bootstrap_tls_ca_pem          = tls_self_signed_cert.bootstrap_tls_ca.cert_pem
    bootstrap_tls_cert_pem        = tls_locally_signed_cert.bootstrap_tls_cert.cert_pem
    bootstrap_tls_private_key_pem = tls_private_key.bootstrap_tls_private_key.private_key_pem

    # Vault Server Configuration
    config_vault_cli = templatefile("${path.module}/templates/vault/cli-config.sh.tftpl", {
      vault_fqdn = var.vault_fqdn
    })

    config_vault_hcl = templatefile("${path.module}/templates/vault/vault.hcl.tftpl", {
      ui                        = var.vault.ui
      disable_mlock             = var.vault.disable_mlock
      cluster_name              = var.vault.cluster_name
      log_level                 = var.vault.log_level
      log_format                = var.vault.log_format
      tls_min_version           = var.vault.listener_tcp.tls_min_version
      prometheus_retention_time = var.vault.telemetry.prometheus_retention_time
      disable_hostname          = var.vault.telemetry.disable_hostname
      vault_fqdn                = var.vault_fqdn
      aws_region                = data.aws_region.current.region
      kms_key_alias             = aws_kms_alias.auto_unseal.name
      auto_join_tag_key         = var.compute.auto_join.tag_key
      auto_join_tag_value       = var.compute.auto_join.tag_value
    })

    config_vault_snapshot_json = templatefile("${path.module}/templates/vault/snapshot.json.tftpl", {
      aws_s3_bucket = aws_s3_bucket.snapshots.id
      aws_s3_region = data.aws_region.current.region
      path_prefix   = var.vault_snapshot.path_prefix
      file_prefix   = var.vault_snapshot.file_prefix
      interval      = var.vault_snapshot.interval
      retain        = var.vault_snapshot.retain
    })

    config_vault_admin_policy = file("${path.module}/files/policies/admin.hcl")

    config_vault_server_policy = templatefile("${path.module}/templates/policies/vault-server.hcl.tftpl", {
      vault_pki_mount_path = var.vault_pki.mount_path
    })

    config_vault_service          = file("${path.module}/files/vault/vault.service")
    config_vault_service_override = file("${path.module}/files/vault/vault.service.override.conf")

    # Vault Agent Configuration
    config_vault_agent_hcl = templatefile("${path.module}/templates/agent/agent.hcl.tftpl", {
      vault_fqdn = var.vault_fqdn
    })

    config_vault_agent_server_tls_ctmpl = templatefile("${path.module}/templates/agent/vault-server-tls.ctmpl.tftpl", {
      vault_fqdn                = var.vault_fqdn
      vault_pki_mount_path      = var.vault_pki.mount_path
      vault_pki_server_cert_ttl = var.vault_pki.server_cert_ttl
    })

    config_vault_agent_service                 = file("${path.module}/files/agent/vault-agent.service")
    config_vault_agent_reload_rules            = file("${path.module}/files/agent/vault-agent-reload.rules")
    config_vault_agent_reload_vault_server_tls = file("${path.module}/files/agent/vault-server-tls-reload.sh")
  }))

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_type           = "gp3"
      volume_size           = var.compute.root_disk.volume_size
      iops                  = var.compute.root_disk.iops
      throughput            = var.compute.root_disk.throughput
      encrypted             = true
      delete_on_termination = true
    }
  }

  # Raft Data Storage Volume
  block_device_mappings {
    device_name = "/dev/xvdf"

    ebs {
      volume_type           = "gp3"
      volume_size           = var.compute.raft_data_disk.volume_size
      iops                  = var.compute.raft_data_disk.iops
      throughput            = var.compute.raft_data_disk.throughput
      encrypted             = true
      delete_on_termination = true
    }
  }

  # Audit Log Storage Volume
  block_device_mappings {
    device_name = "/dev/xvdg"

    ebs {
      volume_type           = "gp3"
      volume_size           = var.compute.audit_disk.volume_size
      iops                  = var.compute.audit_disk.iops
      throughput            = var.compute.audit_disk.throughput
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "volume"

    tags = {
      Name = var.compute.launch_template.volume_name
    }
  }

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = can(regex("(ubuntu|debian)", lower(var.ami.name)))
      error_message = "The provided AMI must be Ubuntu or Debian-based."
    }

    precondition {
      condition = (
        local.root_disk_at_floor ||
        var.compute.root_disk.iops <= data.aws_ec2_instance_type.compute.ebs_performance_baseline_iops
      )
      error_message = format(
        "compute.root_disk.iops (%d) exceeds the %s baseline EBS IOPS (%d). The instance cannot sustain this provisioned IOPS, so you would be billed for unusable capacity. Set iops to %d to match the instance, or choose a larger instance type.",
        var.compute.root_disk.iops,
        var.compute.instance_type,
        data.aws_ec2_instance_type.compute.ebs_performance_baseline_iops,
        data.aws_ec2_instance_type.compute.ebs_performance_baseline_iops,
      )
    }

    precondition {
      condition = (
        local.root_disk_at_floor ||
        var.compute.root_disk.throughput <= data.aws_ec2_instance_type.compute.ebs_performance_baseline_throughput
      )
      error_message = format(
        "compute.root_disk.throughput (%d MiB/s) exceeds the %s baseline EBS throughput (%.1f MiB/s). The instance cannot sustain this provisioned throughput, so you would be billed for unusable capacity. Set throughput to %d to match the instance, or choose a larger instance type.",
        var.compute.root_disk.throughput,
        var.compute.instance_type,
        data.aws_ec2_instance_type.compute.ebs_performance_baseline_throughput,
        floor(data.aws_ec2_instance_type.compute.ebs_performance_baseline_throughput),
      )
    }

    precondition {
      condition = (
        local.raft_data_disk_at_floor ||
        var.compute.raft_data_disk.iops <= data.aws_ec2_instance_type.compute.ebs_performance_baseline_iops
      )
      error_message = format(
        "compute.raft_data_disk.iops (%d) exceeds the %s baseline EBS IOPS (%d). The instance cannot sustain this provisioned IOPS, so you would be billed for unusable capacity. Set iops to %d to match the instance, or choose a larger instance type.",
        var.compute.raft_data_disk.iops,
        var.compute.instance_type,
        data.aws_ec2_instance_type.compute.ebs_performance_baseline_iops,
        data.aws_ec2_instance_type.compute.ebs_performance_baseline_iops,
      )
    }

    precondition {
      condition = (
        local.raft_data_disk_at_floor ||
        var.compute.raft_data_disk.throughput <= data.aws_ec2_instance_type.compute.ebs_performance_baseline_throughput
      )
      error_message = format(
        "compute.raft_data_disk.throughput (%d MiB/s) exceeds the %s baseline EBS throughput (%.1f MiB/s). The instance cannot sustain this provisioned throughput, so you would be billed for unusable capacity. Set throughput to %d to match the instance, or choose a larger instance type.",
        var.compute.raft_data_disk.throughput,
        var.compute.instance_type,
        data.aws_ec2_instance_type.compute.ebs_performance_baseline_throughput,
        floor(data.aws_ec2_instance_type.compute.ebs_performance_baseline_throughput),
      )
    }

    precondition {
      condition = (
        local.audit_disk_at_floor ||
        var.compute.audit_disk.iops <= data.aws_ec2_instance_type.compute.ebs_performance_baseline_iops
      )
      error_message = format(
        "compute.audit_disk.iops (%d) exceeds the %s baseline EBS IOPS (%d). The instance cannot sustain this provisioned IOPS, so you would be billed for unusable capacity. Set iops to %d to match the instance, or choose a larger instance type.",
        var.compute.audit_disk.iops,
        var.compute.instance_type,
        data.aws_ec2_instance_type.compute.ebs_performance_baseline_iops,
        data.aws_ec2_instance_type.compute.ebs_performance_baseline_iops,
      )
    }

    precondition {
      condition = (
        local.audit_disk_at_floor ||
        var.compute.audit_disk.throughput <= data.aws_ec2_instance_type.compute.ebs_performance_baseline_throughput
      )
      error_message = format(
        "compute.audit_disk.throughput (%d MiB/s) exceeds the %s baseline EBS throughput (%.1f MiB/s). The instance cannot sustain this provisioned throughput, so you would be billed for unusable capacity. Set throughput to %d to match the instance, or choose a larger instance type.",
        var.compute.audit_disk.throughput,
        var.compute.instance_type,
        data.aws_ec2_instance_type.compute.ebs_performance_baseline_throughput,
        floor(data.aws_ec2_instance_type.compute.ebs_performance_baseline_throughput),
      )
    }
  }
}

resource "aws_autoscaling_group" "vault_enterprise" {
  name_prefix = var.compute.autoscaling_group.name_prefix

  min_size         = var.compute.node_count
  max_size         = var.compute.node_count
  desired_capacity = var.compute.node_count

  vpc_zone_identifier = local.vpc.private_subnet_ids

  launch_template {
    id      = aws_launch_template.vault_enterprise.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 900

  target_group_arns = [aws_lb_target_group.vault_enterprise.arn]

  instance_refresh {
    strategy = "Rolling"

    preferences {
      # Derived as maximum nodes that can be out during instance
      # refresh while maintaining quorum.
      #  floor((n-1) * 100 / n) gives:
      #   n=3 --> 66% (1 node out, 2 healthy)
      #   n=5 --> 80% (1 node out, 4 healthy)
      min_healthy_percentage = floor(
        (var.compute.node_count - 1) * 100 / var.compute.node_count
      )
    }
  }

  tag {
    key                 = var.compute.auto_join.tag_key
    value               = var.compute.auto_join.tag_value
    propagate_at_launch = true
  }

  tag {
    key                 = "Name"
    value               = var.compute.autoscaling_group.instance_name
    propagate_at_launch = true
  }

  depends_on = [
    aws_iam_role_policy.kms_read_write,
    aws_iam_role_policy.secrets_manager_read,
  ]
}
