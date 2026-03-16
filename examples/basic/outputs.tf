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

output "vault_ca_cert" {
  description = "CA certificate for trusting the Vault TLS chain."
  value       = module.vault.vault_ca_cert
  sensitive   = true
}
