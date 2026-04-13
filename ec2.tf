# Bastion Host

resource "aws_instance" "bastion" {
  ami                         = var.ec2_ami.id
  instance_type               = var.bastion_instance_type
  key_name                    = var.ec2_key_pair_name
  subnet_id                   = local.vpc.public_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault-enterprise-bastion" })
}

# Vault Nodes

resource "aws_launch_template" "vault" {
  name_prefix   = "${var.project_name}-vault-"
  image_id      = var.ec2_ami.id
  instance_type = var.vault_server_instance_type
  key_name      = var.ec2_key_pair_name

  iam_instance_profile {
    name = aws_iam_instance_profile.vault.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.vault.id]
    delete_on_termination       = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64gzip(templatefile("${path.module}/templates/cloud-init.sh.tftpl", {
    region                                = data.aws_region.current.region
    ebs_raft_device_name                  = local.ebs_raft_device_name
    ebs_audit_device_name                 = local.ebs_audit_device_name
    ssm_cluster_state_name                = aws_ssm_parameter.vault_cluster_state.name
    ssm_pki_state_name                    = aws_ssm_parameter.vault_pki_state.name
    ssm_pki_ca_cert_name                  = aws_ssm_parameter.vault_pki_ca_cert.name
    vault_fqdn                            = local.vault_fqdn
    vault_bootstrap_root_token_secret_arn = aws_secretsmanager_secret.vault_bootstrap_root_token.arn

    script_logging                      = local.script_logging
    script_ec2_metadata_helpers         = local.script_ec2_metadata_helpers
    script_secrets_manager_helpers      = local.script_secrets_manager_helpers
    script_ebs_helpers                  = local.script_ebs_helpers
    script_system_setup                 = local.script_system_setup
    script_vault_system                 = local.script_vault_system
    script_vault_install                = local.script_vault_install
    script_vault_get_license            = local.script_vault_get_license
    script_vault_get_bootstrap_root_ca  = local.script_vault_get_bootstrap_root_ca
    script_vault_get_bootstrap_tls_cert = local.script_vault_get_bootstrap_tls_cert
    script_vault_get_bootstrap_tls_key  = local.script_vault_get_bootstrap_tls_key
    script_vault_write_systemd_unit     = local.script_vault_write_systemd_unit
    script_vault_write_license          = local.script_vault_write_license
    script_vault_write_tls_materials    = local.script_vault_write_tls_materials
    script_vault_write_config           = local.script_vault_write_config
    script_vault_write_snapshot_config  = local.script_vault_write_snapshot_config
    script_vault_configure_autopilot    = local.script_vault_configure_autopilot
    script_vault_configure_snapshots    = local.script_vault_configure_snapshots
    script_vault_cluster                = local.script_vault_cluster
    script_vault_pki                    = local.script_vault_pki
    script_vault_aws_auth               = local.script_vault_aws_auth
    script_vault_audit                  = local.script_vault_audit
    script_vault_tls                    = local.script_vault_tls
    script_vault_cli                    = local.script_vault_cli
    script_agent_write_config           = local.script_agent_write_config
    script_agent_write_tls_template     = local.script_agent_write_tls_template
    script_agent_write_reload_script    = local.script_agent_write_reload_script
    script_agent_write_polkit_rules     = local.script_agent_write_polkit_rules
    script_agent_write_systemd_unit     = local.script_agent_write_systemd_unit
    script_agent_start                  = local.script_agent_start
  }))

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_type           = "gp3"
      volume_size           = var.root_volume_size
      encrypted             = true
      delete_on_termination = true
    }
  }

  # Raft Data Storage Volume
  block_device_mappings {
    device_name = "/dev/xvdf"

    ebs {
      volume_type           = var.vault_data_disk.volume_type
      volume_size           = var.vault_data_disk.volume_size
      iops                  = var.vault_data_disk.iops
      throughput            = var.vault_data_disk.throughput
      encrypted             = true
      delete_on_termination = true
    }
  }

  # Audit Log Storage Volume
  block_device_mappings {
    device_name = "/dev/xvdg"

    ebs {
      volume_type           = var.vault_audit_disk.volume_type
      volume_size           = var.vault_audit_disk.volume_size
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(var.common_tags, {
      Name                    = "${var.project_name}-vault-enterprise"
      (local.cluster_tag_key) = local.cluster_tag_value
    })
  }

  tag_specifications {
    resource_type = "volume"

    tags = merge(var.common_tags, {
      Name = "${var.project_name}-vault"
    })
  }

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = can(regex("(ubuntu|debian)", lower(var.ec2_ami.name)))
      error_message = "The provided AMI must be Ubuntu or Debian-based."
    }
  }
}

resource "aws_autoscaling_group" "vault" {
  name_prefix = "${var.project_name}-vault-"

  min_size         = var.vault_node_count
  max_size         = var.vault_node_count
  desired_capacity = var.vault_node_count

  vpc_zone_identifier = local.vpc.private_subnet_ids

  launch_template {
    id      = aws_launch_template.vault.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 900

  target_group_arns = [aws_lb_target_group.vault.arn]

  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = local.instance_refresh_min_healthy_pct
    }
  }

  dynamic "tag" {
    for_each = merge(var.common_tags, {
      (local.cluster_tag_key) = local.cluster_tag_value
    })

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  depends_on = [
    aws_iam_role_policy.vault_kms,
    aws_iam_role_policy.vault_secrets_manager,
  ]
}
