output "vault_url" {
  description = "URL of the Vault cluster."
  value       = "https://${local.vault_fqdn}:8200"
}

output "bastion_public_ip" {
  description = "Public IP of the bastion host."
  value       = aws_instance.bastion.public_ip
}

output "vault_private_ips" {
  description = "Private IPs of the Vault nodes."
  value       = aws_instance.vault[*].private_ip
}

output "vault_kms_key_id" {
  description = "KMS key ID used for Vault auto-unseal."
  value       = aws_kms_key.vault.key_id
}

output "vault_snapshot_bucket" {
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

output "vault_ca_cert" {
  description = "CA certificate for trusting the Vault TLS chain."
  value       = tls_self_signed_cert.ca.cert_pem
  sensitive   = true
}
