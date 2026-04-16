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
    # Environment
    vault_version = var.vault_version
    vault_fqdn    = local.vault_fqdn
    aws_region    = data.aws_region.current.region

    # Prepare Storage
    ebs_raft_device_name  = local.ebs_raft_device_name
    ebs_audit_device_name = local.ebs_audit_device_name

    # Vault Server Configuration
    config_vault_service          = local.config_vault_service
    config_vault_service_override = local.config_vault_service_override
    config_vault_hcl              = local.config_vault_hcl
    config_vault_server_policy    = local.config_vault_server_policy
    config_vault_admin_policy     = local.config_vault_admin_policy

    # Bootstrap Artifacts
    vault_enterprise_license_secret_arn  = aws_secretsmanager_secret.vault_enterprise_license.arn
    bootstrap_tls_ca_cert_secret_arn     = aws_secretsmanager_secret.vault_bootstrap_tls_ca_cert.arn
    bootstrap_tls_cert_secret_arn        = aws_secretsmanager_secret.vault_bootstrap_tls_cert.arn
    bootstrap_tls_private_key_secret_arn = aws_secretsmanager_secret.vault_bootstrap_tls_private_key.arn
    config_vault_snapshot_json           = local.config_vault_snapshot_json

    # Cluster Coordination
    vault_cluster_tag_key                 = local.vault_cluster_tag_key
    vault_cluster_tag_value               = local.vault_cluster_tag_value
    vault_cluster_state_ssm_name          = aws_ssm_parameter.vault_cluster_state.name
    vault_bootstrap_root_token_secret_arn = aws_secretsmanager_secret.vault_bootstrap_root_token.arn
    vault_recovery_keys_secret_arn        = aws_secretsmanager_secret.vault_recovery_keys.arn
    vault_minimum_quorum_size             = var.vault_node_count

    # PKI and TLS
    cluster_name                 = title(var.project_name)
    vault_pki_organization       = var.vault_pki_organization
    vault_pki_country            = var.vault_pki_country
    vault_pki_state_ssm_name     = aws_ssm_parameter.vault_pki_state.name
    vault_tls_ca_bundle_ssm_name = aws_ssm_parameter.vault_tls_ca_bundle.name

    # AWS Auth
    vault_iam_role_arn = aws_iam_role.vault.arn

    # HCP Terraform JWT Auth
    hcp_terraform_hostname     = var.hcp_terraform_hostname
    hcp_terraform_org_name     = var.hcp_terraform_org_name
    hcp_terraform_workspace_id = var.hcp_terraform_workspace_id

    # Vault Agent
    config_agent_hcl                     = local.config_agent_hcl
    config_agent_server_tls_ctmpl        = local.config_agent_server_tls_ctmpl
    config_agent_reload_vault_server_tls = local.config_agent_reload_vault_server_tls
    config_agent_reload_rules            = local.config_agent_reload_rules
    config_agent_service                 = local.config_agent_service
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
      Name                          = "${var.project_name}-vault-enterprise"
      (local.vault_cluster_tag_key) = local.vault_cluster_tag_value
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
      (local.vault_cluster_tag_key) = local.vault_cluster_tag_value
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
