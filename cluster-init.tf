resource "aws_secretsmanager_secret" "vault_root_token" {
  name_prefix = "${var.project_name}-vault-root-token-"
  description = "Vault root token — written at cluster init, revoked after Terraform handoff"

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault-root-token" })
}

resource "aws_secretsmanager_secret" "vault_recovery_keys" {
  name_prefix = "${var.project_name}-vault-recovery-keys-"
  description = "Vault recovery keys — written at cluster init"

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault-recovery-keys" })
}

data "aws_iam_policy_document" "vault_cluster_init" {
  statement {
    sid    = "ClusterInitReadWrite"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
    ]
    resources = [
      aws_secretsmanager_secret.vault_root_token.arn,
      aws_secretsmanager_secret.vault_recovery_keys.arn,
    ]
  }
}

# All nodes receive PutSecretValue because they share a single instance profile.
# In practice only the elected bootstrap node writes to these secrets.
# Acceptable for a lab deployment.
resource "aws_iam_role_policy" "vault_cluster_init" {
  name_prefix = "${var.project_name}-cluster-init-"
  role        = aws_iam_role.vault.id
  policy      = data.aws_iam_policy_document.vault_cluster_init.json
}
