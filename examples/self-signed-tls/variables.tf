variable "vault_enterprise_license" {
  type        = string
  description = "Vault Enterprise license string."
  sensitive   = true
}

variable "route53_zone_name" {
  type        = string
  description = "Name of the Route 53 hosted zone for the Vault DNS record."
}
