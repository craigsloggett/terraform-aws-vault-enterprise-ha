resource "aws_ssm_parameter" "vault_cluster_state" {
  name        = "/${var.project_name}/vault/cluster/state"
  type        = "String"
  value       = "uninitialized"
  description = "Vault cluster initialization state flag (uninitialized | ready)"

  lifecycle {
    ignore_changes = [value]
  }

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault-cluster-state" })
}

resource "aws_ssm_parameter" "vault_pki_state" {
  name        = "/${var.project_name}/vault/pki/state"
  type        = "String"
  value       = "uninitialized"
  description = "Vault PKI bootstrap state flag (uninitialized | ready)"

  lifecycle {
    ignore_changes = [value]
  }

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault-pki-state" })
}

resource "aws_ssm_parameter" "vault_pki_ca_cert" {
  name        = "/${var.project_name}/vault/pki/ca-cert"
  type        = "String"
  value       = "uninitialized"
  description = "Vault PKI CA certificate PEM (public)"

  lifecycle {
    ignore_changes = [value]
  }

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault-pki-ca-cert" })
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
      aws_ssm_parameter.vault_pki_ca_cert.arn,
    ]
  }
}

# All nodes receive PutParameter because they share a single instance profile.
# In practice only the elected bootstrap node writes to this parameter.
# Acceptable for a lab deployment.
resource "aws_iam_role_policy" "vault_ssm" {
  name_prefix = "${var.project_name}-ssm-"
  role        = aws_iam_role.vault.id
  policy      = data.aws_iam_policy_document.vault_ssm.json
}
