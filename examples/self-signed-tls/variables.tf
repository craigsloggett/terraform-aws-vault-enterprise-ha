variable "vault_enterprise_license" {
  type        = string
  description = "Vault Enterprise license string."
  sensitive   = true
}

variable "key_pair_key_name" {
  type        = string
  description = "Name of an existing EC2 key pair for SSH access."
}

variable "existing_vpc_name" {
  type        = string
  description = "Name tag of the existing VPC to deploy into."
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

variable "hcp_terraform_organization_name" {
  type        = string
  description = "HCP Terraform organization name. Leave empty to skip JWT auth configuration."
  default     = ""
}
