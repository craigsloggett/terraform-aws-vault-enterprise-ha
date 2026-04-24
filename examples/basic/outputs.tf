output "vault_url" {
  description = "URL of the Vault cluster."
  value       = module.vault.vault_url
}

output "bastion_public_ip" {
  description = "Public IP of the bastion host."
  value       = module.vault.bastion_public_ip
}