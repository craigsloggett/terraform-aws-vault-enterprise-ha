# Bastion Host

resource "aws_instance" "bastion" {
  ami                         = var.ec2_instance_ami_id
  instance_type               = var.bastion_instance_type
  key_name                    = var.ec2_key_pair_name
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = merge(var.common_tags, { Name = "${var.project_name}-bastion" })
}

# Vault Nodes

resource "aws_instance" "vault" {
  count = local.vault_node_count

  ami                    = var.ec2_instance_ami_id
  instance_type          = var.vault_instance_type
  key_name               = var.ec2_key_pair_name
  subnet_id              = module.vpc.private_subnets[count.index]
  vpc_security_group_ids = [aws_security_group.vault.id]
  iam_instance_profile   = aws_iam_instance_profile.vault.name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = templatefile("${path.module}/templates/cloud-init.sh.tftpl", {
    vault_version                = var.vault_package_version
    vault_fqdn                   = trimsuffix(aws_route53_record.vault.fqdn, ".")
    node_id                      = "vault-${count.index}"
    region                       = data.aws_region.current.name
    kms_key_alias                = aws_kms_alias.vault.name
    vault_license_secret_arn     = aws_secretsmanager_secret.vault_license.arn
    vault_ca_cert_secret_arn     = aws_secretsmanager_secret.vault_ca_cert.arn
    vault_server_cert_secret_arn = aws_secretsmanager_secret.vault_server_cert.arn
    vault_server_key_secret_arn  = aws_secretsmanager_secret.vault_server_key.arn
    cluster_tag_key              = local.cluster_tag_key
    cluster_tag_value            = local.cluster_tag_value
    ebs_device_name              = local.ebs_device_name
  })

  tags = merge(var.common_tags, {
    Name                    = "${var.project_name}-vault-${count.index}"
    (local.cluster_tag_key) = local.cluster_tag_value
  })

  depends_on = [
    aws_iam_role_policy.vault_kms,
    aws_iam_role_policy.vault_secrets_manager,
  ]

  lifecycle {
    precondition {
      condition     = can(regex("(ubuntu|debian)", lower(data.aws_ami.selected.name)))
      error_message = "The provided AMI must be Ubuntu or Debian-based."
    }
  }
}

# EBS Volumes for Raft Storage

resource "aws_ebs_volume" "vault" {
  count = local.vault_node_count

  availability_zone = local.azs[count.index]
  size              = var.vault_ebs_volume_size
  type              = "gp3"
  encrypted         = true

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault-data-${count.index}" })
}

resource "aws_volume_attachment" "vault" {
  count = local.vault_node_count

  device_name = local.ebs_device_name
  volume_id   = aws_ebs_volume.vault[count.index].id
  instance_id = aws_instance.vault[count.index].id
}
