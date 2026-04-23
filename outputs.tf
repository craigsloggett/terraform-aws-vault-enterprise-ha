output "vault_url" {
  description = "URL of the Vault cluster."
  value       = "https://${local.vault_fqdn}"
}

output "vault_version" {
  description = "Vault Enterprise version deployed."
  value       = var.vault_version
}

output "bastion_public_ip" {
  description = "Public IP of the bastion host."
  value       = aws_instance.bastion.public_ip
}

output "vault_asg_name" {
  description = "Name of the Vault Auto Scaling Group."
  value       = aws_autoscaling_group.vault.name
}

output "vault_kms_key_id" {
  description = "KMS key ID used for Vault auto-unseal."
  value       = aws_kms_key.vault.key_id
}

output "vault_snapshots_bucket" {
  description = "S3 bucket for Vault snapshots."
  value       = aws_s3_bucket.vault_snapshots.id
}

output "vault_target_group_arn" {
  description = "ARN of the Vault NLB target group."
  value       = aws_lb_target_group.vault.arn
}

output "ec2_ami_name" {
  description = "Name of the AMI used for EC2 instances."
  value       = var.ec2_ami.name
}

output "vault_tls_ca_bundle_ssm_parameter_name" {
  description = "SSM Parameter for the Vault PKI managed TLS CA bundle."
  value       = aws_ssm_parameter.vault_tls_ca_bundle.name
}

output "vault_iam_role_name" {
  description = "Name of the Vault server IAM role."
  value       = aws_iam_role.vault.name
}

output "vault_jwt_auth_path" {
  description = "Vault JWT auth method path for HCP Terraform (TFC_VAULT_AUTH_PATH)."
  value       = var.hcp_terraform.jwt_auth_path
}

output "vault_jwt_auth_role_name" {
  description = "Vault JWT auth role name for HCP Terraform (TFC_VAULT_RUN_ROLE)."
  value       = var.hcp_terraform.jwt_auth_role_name
}

output "intermediate_csr_ssm_parameter_name" {
  description = "SSM parameter name where the intermediate CSR is published."
  value       = local.intermediate_csr_ssm_name
}

output "intermediate_ca_secret_arn" {
  description = "Secrets Manager ARN for the signed intermediate CA certificate."
  value       = var.intermediate_ca_secret_arn
}
