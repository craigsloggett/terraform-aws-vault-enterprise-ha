output "vault_url" {
  description = "URL of the Vault Enterprise cluster."
  value       = "https://${local.vault_fqdn}"
}

output "vault_version" {
  description = "Vault Enterprise version deployed."
  value       = var.vault.version
}

output "bastion_public_ip" {
  description = "Public IP of the bastion host."
  value       = aws_instance.bastion.public_ip
}

output "vault_cluster_autoscaling_group_name" {
  description = "Name of the Vault Enterprise Auto Scaling Group."
  value       = aws_autoscaling_group.vault_enterprise.name
}

output "ami_name" {
  description = "Name of the AMI used for EC2 instances."
  value       = var.ami.name
}

output "vault_snapshot_aws_s3_bucket_name" {
  description = "Name of the S3 bucket for Vault Enterprise snapshots."
  value       = aws_s3_bucket.snapshots.id
}

output "bootstrap_cluster_state_ssm_parameter_name" {
  description = "SSM Parameter for the bootstrap initialization state flag."
  value       = aws_ssm_parameter.bootstrap_cluster_state.name
}

output "bootstrap_pki_state_ssm_parameter_name" {
  description = "SSM Parameter for the bootstrap PKI state flag."
  value       = aws_ssm_parameter.bootstrap_pki_state.name
}

output "vault_pki_intermediate_ca_ssm_parameter_name" {
  description = "SSM Parameter for the Vault PKI intermediate CA PEM."
  value       = aws_ssm_parameter.vault_pki_intermediate_ca.name
}

output "vault_pki_intermediate_ca_csr_ssm_parameter_name" {
  description = "SSM parameter name where the Vault PKI intermediate CA CSR is published."
  value       = aws_ssm_parameter.vault_pki_intermediate_ca_csr.name
}

output "vault_pki_signed_intermediate_ca_secret_arn" {
  description = "Secrets Manager ARN for the Vault PKI signed intermediate CA PEM."
  value       = aws_secretsmanager_secret.vault_pki_signed_intermediate_ca.arn
}

output "hcp_terraform_jwt_auth_mount_path" {
  description = "Vault JWT auth method path for HCP Terraform (TFC_VAULT_AUTH_PATH)."
  value       = var.hcp_terraform_jwt_auth.mount_path
}

output "hcp_terraform_jwt_auth_role_name" {
  description = "Vault JWT auth role name for HCP Terraform (TFC_VAULT_RUN_ROLE)."
  value       = var.hcp_terraform_jwt_auth.role_name
}
