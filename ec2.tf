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

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault-bastion" })
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
    vault_version                = var.vault_version
    region                       = data.aws_region.current.region
    ebs_device_name              = local.ebs_device_name
    vault_license_secret_arn     = aws_secretsmanager_secret.vault_license.arn
    vault_ca_cert_secret_arn     = aws_secretsmanager_secret.vault_ca_cert.arn
    vault_server_cert_secret_arn = aws_secretsmanager_secret.vault_server_cert.arn
    vault_server_key_secret_arn  = aws_secretsmanager_secret.vault_server_key.arn

    cluster_tag_key                = local.cluster_tag_key
    cluster_tag_value              = local.cluster_tag_value
    ssm_cluster_state_name         = aws_ssm_parameter.vault_cluster_state.name
    ssm_pki_state_name             = aws_ssm_parameter.vault_pki_state.name
    ssm_pki_ca_cert_name           = aws_ssm_parameter.vault_pki_ca_cert.name
    vault_fqdn                     = local.vault_fqdn
    vault_iam_role_arn             = aws_iam_role.vault.arn
    vault_root_token_secret_arn    = aws_secretsmanager_secret.vault_root_token.arn
    vault_recovery_keys_secret_arn = aws_secretsmanager_secret.vault_recovery_keys.arn

    config_vault_hcl = templatefile("${path.module}/templates/vault.hcl.tftpl", {
      cluster_name      = var.project_name
      vault_fqdn        = trimsuffix(aws_route53_record.vault.fqdn, ".")
      region            = data.aws_region.current.region
      kms_key_alias     = aws_kms_alias.vault.name
      cluster_tag_key   = local.cluster_tag_key
      cluster_tag_value = local.cluster_tag_value
      min_quorum        = local.vault_node_count
    })

    config_vault_service          = local.config_vault_service
    config_vault_service_override = local.config_vault_service_override
    config_snapshot_json          = local.config_snapshot_json
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

  tag_specifications {
    resource_type = "instance"

    tags = merge(var.common_tags, {
      Name                    = "${var.project_name}-vault"
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

# EBS Raft storage: with an ASG, pre-provisioned EBS volumes cannot be reliably
# attached to replacement instances without additional automation (e.g. a lifecycle
# hook + Lambda). For this lab deployment, Raft data is stored on the instance root
# volume. In a production deployment, consider one of:
#   a. A lifecycle hook that attaches a tagged EBS volume on instance launch.
#   b. NFS-backed Raft (not recommended for performance).
#   c. Reverting to fixed aws_instance resources with automated replacement.
# The cloud-init script's mount_data_volume function is retained for forward
# compatibility but will not find an additional EBS device and will exit cleanly
# if none is attached (see mount_data_volume in cloud-init.sh.tftpl).

resource "aws_autoscaling_group" "vault" {
  name_prefix = "${var.project_name}-vault-"

  min_size         = local.vault_node_count
  max_size         = local.vault_node_count
  desired_capacity = local.vault_node_count

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
