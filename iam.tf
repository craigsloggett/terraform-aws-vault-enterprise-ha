data "aws_iam_policy_document" "vault_server_assume_role" {
  statement {
    sid     = "EC2InstanceAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vault_server" {
  name               = var.vault_server_iam_resource_names.role
  assume_role_policy = data.aws_iam_policy_document.vault_server_assume_role.json
}

resource "aws_iam_instance_profile" "vault_server" {
  name = var.vault_server_iam_resource_names.instance_profile
  role = aws_iam_role.vault_server.name
}

data "aws_iam_policy_document" "vault_server_kms_read_write" {
  statement {
    sid    = "AutoUnsealSealOperations"
    effect = "Allow"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
    ]

    resources = [aws_kms_key.vault.arn]
  }
}

resource "aws_iam_role_policy" "vault_server_kms_read_write" {
  name   = var.vault_server_iam_resource_names.kms_read_write_policy
  role   = aws_iam_role.vault_server.id
  policy = data.aws_iam_policy_document.vault_server_kms_read_write.json
}

data "aws_iam_policy_document" "vault_server_kms_describe" {
  statement {
    sid       = "AutoUnsealKeyValidation"
    effect    = "Allow"
    actions   = ["kms:DescribeKey"]
    resources = [aws_kms_key.vault.arn]
  }
}

resource "aws_iam_role_policy" "vault_server_kms_describe" {
  name   = var.vault_server_iam_resource_names.kms_describe_policy
  role   = aws_iam_role.vault_server.id
  policy = data.aws_iam_policy_document.vault_server_kms_describe.json
}

data "aws_iam_policy_document" "vault_server_secrets_manager_read" {
  statement {
    sid     = "BootstrapMaterialRead"
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]

    resources = [
      aws_secretsmanager_secret.bootstrap_tls_ca.arn,
      aws_secretsmanager_secret.bootstrap_tls_cert.arn,
      aws_secretsmanager_secret.bootstrap_tls_private_key.arn,
      aws_secretsmanager_secret.vault_enterprise_license.arn,
      aws_secretsmanager_secret.vault_pki_intermediate_ca_signed_csr.arn
    ]
  }
}

resource "aws_iam_role_policy" "vault_server_secrets_manager_read" {
  name   = var.vault_server_iam_resource_names.secrets_manager_read_policy
  role   = aws_iam_role.vault_server.id
  policy = data.aws_iam_policy_document.vault_server_secrets_manager_read.json
}

data "aws_iam_policy_document" "vault_server_secrets_manager_describe" {
  statement {
    sid       = "IntermediateCASignedCSRPolling"
    effect    = "Allow"
    actions   = ["secretsmanager:DescribeSecret"]
    resources = [aws_secretsmanager_secret.vault_pki_intermediate_ca_signed_csr.arn]
  }
}

resource "aws_iam_role_policy" "vault_server_secrets_manager_describe" {
  name   = var.vault_server_iam_resource_names.secrets_manager_describe_policy
  role   = aws_iam_role.vault_server.id
  policy = data.aws_iam_policy_document.vault_server_secrets_manager_describe.json
}

data "aws_iam_policy_document" "vault_server_secrets_manager_read_write" {
  statement {
    sid    = "ClusterInitOutputPersistence"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
    ]

    resources = [
      aws_secretsmanager_secret.vault_server_bootstrap_root_token.arn,
      aws_secretsmanager_secret.vault_recovery_keys.arn,
    ]
  }
}

resource "aws_iam_role_policy" "vault_server_secrets_manager_read_write" {
  name   = var.vault_server_iam_resource_names.secrets_manager_read_write_policy
  role   = aws_iam_role.vault_server.id
  policy = data.aws_iam_policy_document.vault_server_secrets_manager_read_write.json
}

data "aws_iam_policy_document" "vault_server_s3_read_write" {
  statement {
    sid    = "RaftSnapshotObjectManagement"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]

    resources = ["${aws_s3_bucket.vault_snapshots.arn}/*"]
  }
}

resource "aws_iam_role_policy" "vault_server_s3_read_write" {
  name   = var.vault_server_iam_resource_names.s3_read_write_policy
  role   = aws_iam_role.vault_server.id
  policy = data.aws_iam_policy_document.vault_server_s3_read_write.json
}

data "aws_iam_policy_document" "vault_server_s3_list" {
  statement {
    sid       = "RaftSnapshotEnumeration"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.vault_snapshots.arn]
  }
}

resource "aws_iam_role_policy" "vault_server_s3_list" {
  name   = var.vault_server_iam_resource_names.s3_list_policy
  role   = aws_iam_role.vault_server.id
  policy = data.aws_iam_policy_document.vault_server_s3_list.json
}

data "aws_iam_policy_document" "vault_server_ec2_describe" {
  statement {
    sid       = "RaftAutoJoinDiscovery"
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "vault_server_ec2_describe" {
  name   = var.vault_server_iam_resource_names.ec2_describe_policy
  role   = aws_iam_role.vault_server.id
  policy = data.aws_iam_policy_document.vault_server_ec2_describe.json
}

data "aws_iam_policy_document" "vault_server_ssm_read_write" {
  statement {
    sid    = "ClusterCoordinationState"
    effect = "Allow"

    actions = [
      "ssm:GetParameter",
      "ssm:PutParameter",
    ]

    resources = [
      aws_ssm_parameter.vault_cluster_state.arn,
      aws_ssm_parameter.vault_pki_state.arn,
      aws_ssm_parameter.vault_tls_ca_bundle.arn,
      aws_ssm_parameter.vault_pki_intermediate_ca_csr.arn,
    ]
  }
}

resource "aws_iam_role_policy" "vault_server_ssm_read_write" {
  name   = var.vault_server_iam_resource_names.ssm_read_write_policy
  role   = aws_iam_role.vault_server.id
  policy = data.aws_iam_policy_document.vault_server_ssm_read_write.json
}

data "aws_iam_policy_document" "vault_server_iam_read" {
  statement {
    sid    = "ResolveIAMRoleARN"
    effect = "Allow"

    actions = [
      "iam:GetRole",
    ]

    resources = [aws_iam_role.vault_server.arn]
  }
}

resource "aws_iam_role_policy" "vault_server_iam_read" {
  name   = var.vault_server_iam_resource_names.iam_read_policy
  role   = aws_iam_role.vault_server.id
  policy = data.aws_iam_policy_document.vault_server_iam_read.json
}
