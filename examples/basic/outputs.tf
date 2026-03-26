output "vault_url" {
  description = "URL of the Vault cluster."
  value       = module.vault.vault_url
}

output "bastion_public_ip" {
  description = "Public IP of the bastion host."
  value       = module.vault.bastion_public_ip
}

output "vault_private_ips" {
  description = "Private IPs of the Vault nodes."
  value       = module.vault.vault_private_ips
}

output "vault_target_group_arn" {
  description = "ARN of the Vault NLB target group."
  value       = module.vault.vault_target_group_arn
}

output "ec2_ami_name" {
  description = "Name of the AMI used for EC2 instances."
  value       = module.vault.ec2_ami_name
}

output "vault_snapshot_bucket" {
  description = "S3 bucket for Vault snapshots."
  value       = module.vault.vault_snapshot_bucket
}

output "vault_ca_cert" {
  description = "CA certificate for trusting the Vault TLS chain."
  value       = module.vault.vault_ca_cert
  sensitive   = true
}
