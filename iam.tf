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

# KMS (auto-unseal)

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

# Secrets Manager (certs, license)

data "aws_iam_policy_document" "vault_secrets_manager" {
  statement {
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.vault_license.arn,
      aws_secretsmanager_secret.vault_ca_cert.arn,
      aws_secretsmanager_secret.vault_server_cert.arn,
      aws_secretsmanager_secret.vault_server_key.arn,
    ]
  }
}

resource "aws_iam_role_policy" "vault_secrets_manager" {
  name_prefix = "${var.project_name}-secrets-"
  role        = aws_iam_role.vault.id
  policy      = data.aws_iam_policy_document.vault_secrets_manager.json
}

# S3 (snapshots)

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

# EC2 (Raft auto-join)

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
