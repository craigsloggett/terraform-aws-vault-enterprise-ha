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

  tags = {
    Name = var.vault_aws_resource_names.bastion_instance_name
  }
}

# Vault Nodes

resource "aws_launch_template" "vault" {
  name_prefix   = "${var.project_name}-vault-"
  image_id      = var.ec2_ami.id
  instance_type = var.vault_server_instance_type
  key_name      = var.ec2_key_pair_name

  iam_instance_profile {
    name = aws_iam_instance_profile.vault_server.name
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
    # Environment Configuration
    vault_fqdn                          = local.vault_fqdn
    vault_version                       = var.vault_version
    vault_enterprise_license_secret_arn = aws_secretsmanager_secret.vault_enterprise_license.arn

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

    # Cluster Coordination Configuration
    vault_cluster_auto_join_tag_key       = local.vault_cluster_auto_join_tag_key
    vault_cluster_auto_join_tag_value     = local.vault_cluster_auto_join_tag_value
    vault_cluster_state_ssm_name          = aws_ssm_parameter.vault_cluster_state.name
    vault_bootstrap_root_token_secret_arn = aws_secretsmanager_secret.vault_server_bootstrap_root_token.arn
    vault_recovery_keys_secret_arn        = aws_secretsmanager_secret.vault_recovery_keys.arn
    vault_minimum_quorum_size             = var.vault_node_count

    # PKI and TLS Configuration
    vault_pki_state_ssm_name                           = aws_ssm_parameter.vault_pki_state.name
    vault_tls_ca_bundle_ssm_name                       = aws_ssm_parameter.vault_tls_ca_bundle.name
    vault_pki_intermediate_ca_common_name              = var.vault_pki_intermediate_ca.common_name
    vault_pki_intermediate_ca_country                  = var.vault_pki_intermediate_ca.country
    vault_pki_intermediate_ca_organization             = var.vault_pki_intermediate_ca.organization
    vault_pki_intermediate_ca_key_type                 = var.vault_pki_intermediate_ca.key_type
    vault_pki_intermediate_ca_key_bits                 = var.vault_pki_intermediate_ca.key_bits
    vault_pki_intermediate_ca_csr_ssm_name             = aws_ssm_parameter.vault_pki_intermediate_ca_csr.name
    vault_pki_signed_intermediate_wait_timeout_seconds = var.vault_pki_signed_intermediate_wait_timeout_seconds
    vault_pki_intermediate_ca_signed_csr_secret_arn    = aws_secretsmanager_secret.vault_pki_intermediate_ca_signed_csr.arn
    vault_pki_vault_mount_max_ttl                      = var.vault_pki_vault_mount_max_ttl
    vault_pki_vault_server_role_max_ttl                = var.vault_pki_vault_server_role_max_ttl
    vault_pki_server_cert_ttl                          = var.vault_pki_server_cert_ttl
    vault_pki_mount_path                               = var.vault_pki_mount_path

    # AWS Auth Configuration
    vault_iam_role_arn          = aws_iam_role.vault_server.arn
    vault_aws_auth_role_max_ttl = var.vault_aws_auth_role_max_ttl
    vault_aws_auth_role_ttl     = var.vault_aws_auth_role_ttl

    # HCP Terraform JWT Auth Configuration
    hcp_terraform_jwt_auth_hostname              = var.hcp_terraform_jwt_auth.hostname
    hcp_terraform_jwt_auth_organization_name     = var.hcp_terraform_jwt_auth.organization_name
    hcp_terraform_jwt_auth_workspace_id          = var.hcp_terraform_jwt_auth.workspace_id
    hcp_terraform_jwt_auth_oidc_discovery_ca_pem = var.hcp_terraform_jwt_auth.oidc_discovery_ca_pem
    hcp_terraform_jwt_auth_mount_path            = var.hcp_terraform_jwt_auth.mount_path
    hcp_terraform_jwt_auth_role_name             = var.hcp_terraform_jwt_auth.role_name
    vault_jwt_auth_role_max_ttl                  = var.vault_jwt_auth_role_max_ttl
    vault_jwt_auth_role_ttl                      = var.vault_jwt_auth_role_ttl

    # Vault Agent Configuration
    config_vault_agent_hcl                     = local.config_vault_agent_hcl
    config_vault_agent_server_tls_ctmpl        = local.config_vault_agent_server_tls_ctmpl
    config_vault_agent_reload_vault_server_tls = local.config_vault_agent_reload_vault_server_tls
    config_vault_agent_reload_rules            = local.config_vault_agent_reload_rules
    config_vault_agent_service                 = local.config_vault_agent_service
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
    resource_type = "volume"

    tags = {
      Name = var.vault_aws_resource_names.vault_server_volume_name
    }
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

  tag {
    key                 = local.vault_cluster_auto_join_tag_key
    value               = local.vault_cluster_auto_join_tag_value
    propagate_at_launch = true
  }

  tag {
    key                 = "Name"
    value               = var.vault_aws_resource_names.vault_server_instance_name
    propagate_at_launch = true
  }

  depends_on = [
    aws_iam_role_policy.vault_server_kms_read_write,
    aws_iam_role_policy.vault_server_secrets_manager_read,
  ]
}
