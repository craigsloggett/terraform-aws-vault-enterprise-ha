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
    vault_bootstrap_script = templatefile("${path.module}/templates/vault-bootstrap.sh.tftpl", {
      # Environment Configuration
      vault_fqdn         = local.vault_fqdn
      vault_version      = var.vault.version
      license_secret_arn = aws_secretsmanager_secret.license.arn

      # EBS Configuration
      ebs_raft_device_name  = local.ebs_raft_device_name
      ebs_audit_device_name = local.ebs_audit_device_name

      # Vault Server Configuration
      config_vault_service          = local.config_vault_service
      config_vault_service_override = local.config_vault_service_override
      config_vault_admin_policy     = local.config_vault_admin_policy
      config_vault_server_policy    = local.config_vault_server_policy
      config_vault_hcl              = local.config_vault_hcl
      config_vault_snapshot_json    = local.config_vault_snapshot_json

      # Bootstrap Artifacts
      bootstrap_tls_ca_secret_arn          = aws_secretsmanager_secret.bootstrap_tls_ca.arn
      bootstrap_tls_cert_secret_arn        = aws_secretsmanager_secret.bootstrap_tls_cert.arn
      bootstrap_tls_private_key_secret_arn = aws_secretsmanager_secret.bootstrap_tls_private_key.arn

      # Bootstrap Coordination Configuration
      auto_join_tag_key            = var.compute.auto_join.tag_key
      auto_join_tag_value          = var.compute.auto_join.tag_value
      bootstrap_cluster_state_name = aws_ssm_parameter.bootstrap_cluster_state.name
      bootstrap_pki_state_name     = aws_ssm_parameter.bootstrap_pki_state.name
      root_token_secret_arn        = aws_secretsmanager_secret.root_token.arn
      recovery_keys_secret_arn     = aws_secretsmanager_secret.recovery_keys.arn

      # Autopilot Configuration
      vault_autopilot_cleanup_dead_servers               = var.vault_autopilot.cleanup_dead_servers
      vault_autopilot_dead_server_last_contact_threshold = var.vault_autopilot.dead_server_last_contact_threshold
      vault_autopilot_min_quorum                         = max(3, floor(var.compute.node_count / 2) + 1)

      # PKI and TLS Configuration
      vault_pki_intermediate_ca_common_name               = var.vault_pki.intermediate_ca.common_name
      vault_pki_intermediate_ca_country                   = var.vault_pki.intermediate_ca.country
      vault_pki_intermediate_ca_organization              = var.vault_pki.intermediate_ca.organization
      vault_pki_intermediate_ca_key_type                  = var.vault_pki.intermediate_ca.key_type
      vault_pki_intermediate_ca_key_bits                  = var.vault_pki.intermediate_ca.key_bits
      vault_pki_signed_intermediate_poll_interval_seconds = var.vault_pki.signed_intermediate_poll_interval_seconds
      vault_pki_signed_intermediate_wait_timeout_seconds  = var.vault_pki.signed_intermediate_wait_timeout_seconds
      vault_pki_intermediate_ca_ssm_parameter_name        = aws_ssm_parameter.vault_pki_intermediate_ca.name
      vault_pki_intermediate_ca_csr_ssm_parameter_name    = aws_ssm_parameter.vault_pki_intermediate_ca_csr.name
      vault_pki_signed_intermediate_ca_secret_arn         = aws_secretsmanager_secret.vault_pki_signed_intermediate_ca.arn
      vault_pki_vault_mount_max_ttl                       = var.vault_pki.mount_max_ttl
      vault_pki_vault_server_role_max_ttl                 = var.vault_pki.server_role_max_ttl
      vault_pki_server_cert_ttl                           = var.vault_pki.server_cert_ttl
      vault_pki_mount_path                                = var.vault_pki.mount_path

      # AWS Auth Configuration
      vault_iam_role_arn          = aws_iam_role.vault_enterprise.arn
      vault_aws_auth_role_max_ttl = var.vault_auth.aws.role_max_ttl
      vault_aws_auth_role_ttl     = var.vault_auth.aws.role_ttl

      # HCP Terraform JWT Auth Configuration
      vault_auth_jwt_role_max_ttl                        = var.vault_auth.jwt.role_max_ttl
      vault_auth_jwt_role_ttl                            = var.vault_auth.jwt.role_ttl
      vault_auth_jwt_hcp_terraform_hostname              = var.vault_auth_jwt_hcp_terraform.hostname
      vault_auth_jwt_hcp_terraform_organization_name     = var.vault_auth_jwt_hcp_terraform.organization_name
      vault_auth_jwt_hcp_terraform_workspace_id          = var.vault_auth_jwt_hcp_terraform.workspace_id
      vault_auth_jwt_hcp_terraform_oidc_discovery_ca_pem = var.vault_auth_jwt_hcp_terraform.oidc_discovery_ca_pem
      vault_auth_jwt_hcp_terraform_mount_path            = var.vault_auth_jwt_hcp_terraform.mount_path
      vault_auth_jwt_hcp_terraform_role_name             = var.vault_auth_jwt_hcp_terraform.role_name

      # Vault Agent Configuration
      config_vault_agent_hcl                     = local.config_vault_agent_hcl
      config_vault_agent_server_tls_ctmpl        = local.config_vault_agent_server_tls_ctmpl
      config_vault_agent_reload_vault_server_tls = local.config_vault_agent_reload_vault_server_tls
      config_vault_agent_reload_rules            = local.config_vault_agent_reload_rules
      config_vault_agent_service                 = local.config_vault_agent_service
    })
  }))

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_type           = "gp3"
      volume_size           = var.compute.root_volume_size
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
      min_healthy_percentage = local.instance_refresh_min_healthy_pct
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
