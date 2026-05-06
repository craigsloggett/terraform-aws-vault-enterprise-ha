variable "vault_enterprise_license" {
  type        = string
  description = "Vault Enterprise license string."
  sensitive   = true
}

variable "route53_zone_name" {
  type        = string
  description = "Name of the Route 53 hosted zone for the Vault DNS record."
}

variable "ami_name" {
  type        = string
  description = "AMI name filter for the EC2 AMI data source."
}

variable "ami_owner" {
  type        = string
  description = "AWS account ID that owns the AMI."
}
