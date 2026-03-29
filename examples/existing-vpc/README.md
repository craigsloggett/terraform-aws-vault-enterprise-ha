# Example - Existing VPC

This example deploys Vault Enterprise into a pre-existing VPC, discovered by its Name tag. The existing VPC must already have the required VPC endpoints: Secrets Manager, KMS, and EC2 (Interface), S3 (Gateway).

```hcl
data "aws_vpc" "selected" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
  filter {
    name   = "tag:Name"
    values = ["${var.vpc_name}-private-*"]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
  filter {
    name   = "tag:Name"
    values = ["${var.vpc_name}-public-*"]
  }
}

data "aws_route53_zone" "selected" {
  name = var.route53_zone_name
}

data "aws_ami" "selected" {
  most_recent = true
  owners      = [var.ec2_ami_owner]

  filter {
    name   = "name"
    values = [var.ec2_ami_name]
  }
}

module "vault" {
  source = "git::https://github.com/craigsloggett/terraform-aws-vault-enterprise"

  project_name      = var.project_name
  route53_zone      = data.aws_route53_zone.selected
  vault_license     = var.vault_license
  ec2_key_pair_name = var.ec2_key_pair_name
  ec2_ami           = data.aws_ami.selected

  nlb_internal            = var.nlb_internal
  vault_api_allowed_cidrs = var.vault_api_allowed_cidrs

  existing_vpc = {
    vpc_id             = data.aws_vpc.selected.id
    private_subnet_ids = data.aws_subnets.private.ids
    public_subnet_ids  = data.aws_subnets.public.ids
  }
}
```
