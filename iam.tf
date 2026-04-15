data "aws_iam_policy_document" "vault_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vault" {
  name_prefix        = "${var.project_name}-vault-"
  assume_role_policy = data.aws_iam_policy_document.vault_assume_role.json

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault" })
}

resource "aws_iam_instance_profile" "vault" {
  name_prefix = "${var.project_name}-vault-"
  role        = aws_iam_role.vault.name

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault" })
}

data "aws_iam_policy_document" "vault_kms" {
  statement {
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = [aws_kms_key.vault.arn]
  }
}

resource "aws_iam_role_policy" "vault_kms" {
  name_prefix = "${var.project_name}-kms-"
  role        = aws_iam_role.vault.id
  policy      = data.aws_iam_policy_document.vault_kms.json
}

data "aws_iam_policy_document" "vault_secrets_manager" {
  statement {
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.vault_license.arn,
      aws_secretsmanager_secret.vault_bootstrap_tls_ca_cert.arn,
      aws_secretsmanager_secret.vault_bootstrap_tls_cert.arn,
      aws_secretsmanager_secret.vault_bootstrap_tls_private_key.arn,
    ]
  }
}

resource "aws_iam_role_policy" "vault_secrets_manager" {
  name_prefix = "${var.project_name}-secrets-"
  role        = aws_iam_role.vault.id
  policy      = data.aws_iam_policy_document.vault_secrets_manager.json
}

data "aws_iam_policy_document" "vault_s3" {
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:DeleteObject",
    ]
    resources = [
      aws_s3_bucket.vault_snapshots.arn,
      "${aws_s3_bucket.vault_snapshots.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "vault_s3" {
  name_prefix = "${var.project_name}-s3-"
  role        = aws_iam_role.vault.id
  policy      = data.aws_iam_policy_document.vault_s3.json
}

data "aws_iam_policy_document" "vault_ec2_describe" {
  statement {
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "vault_ec2_describe" {
  name_prefix = "${var.project_name}-ec2-"
  role        = aws_iam_role.vault.id
  policy      = data.aws_iam_policy_document.vault_ec2_describe.json
}

data "aws_iam_policy_document" "vault_bootstrap_root_token" {
  statement {
    sid    = "BootstrapRootTokenReadWrite"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
    ]
    resources = [aws_secretsmanager_secret.vault_bootstrap_root_token.arn]
  }
}

resource "aws_iam_role_policy" "vault_bootstrap_root_token" {
  name_prefix = "${var.project_name}-bootstrap-root-token-"
  role        = aws_iam_role.vault.id
  policy      = data.aws_iam_policy_document.vault_bootstrap_root_token.json
}

data "aws_iam_policy_document" "vault_recovery_keys" {
  statement {
    sid    = "RecoveryKeysReadWrite"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
    ]
    resources = [aws_secretsmanager_secret.vault_recovery_keys.arn]
  }
}

resource "aws_iam_role_policy" "vault_recovery_keys" {
  name_prefix = "${var.project_name}-recovery-keys-"
  role        = aws_iam_role.vault.id
  policy      = data.aws_iam_policy_document.vault_recovery_keys.json
}

data "aws_iam_policy_document" "vault_ssm" {
  statement {
    sid    = "ClusterStateReadWrite"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:PutParameter",
    ]
    resources = [
      aws_ssm_parameter.vault_cluster_state.arn,
      aws_ssm_parameter.vault_pki_state.arn,
      aws_ssm_parameter.vault_pki_root_ca_cert.arn,
    ]
  }
}

resource "aws_iam_role_policy" "vault_ssm" {
  name_prefix = "${var.project_name}-ssm-"
  role        = aws_iam_role.vault.id
  policy      = data.aws_iam_policy_document.vault_ssm.json
}

data "aws_iam_policy_document" "vault_iam_read" {
  statement {
    sid    = "ResolveIAMRoleARN"
    effect = "Allow"
    actions = [
      "iam:GetRole",
    ]
    resources = [aws_iam_role.vault.arn]
  }
}

resource "aws_iam_role_policy" "vault_iam_read" {
  name_prefix = "${var.project_name}-iam-read-"
  role        = aws_iam_role.vault.id
  policy      = data.aws_iam_policy_document.vault_iam_read.json
}
