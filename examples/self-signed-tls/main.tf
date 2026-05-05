data "aws_region" "this" {}

data "aws_vpc" "selected" {
  filter {
    name   = "tag:Name"
    values = [var.existing_vpc_name]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
  filter {
    name   = "tag:Name"
    values = ["${var.existing_vpc_name}-private-*"]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
  filter {
    name   = "tag:Name"
    values = ["${var.existing_vpc_name}-public-*"]
  }
}

data "aws_route53_zone" "vault" {
  name = var.route53_zone_name
}

data "aws_ami" "selected" {
  most_recent = true
  owners      = [var.ami_owner]

  filter {
    name   = "name"
    values = [var.ami_name]
  }
}

data "aws_key_pair" "selected" {
  key_name = var.key_pair_key_name
}

module "vault" {
  # tflint-ignore: terraform_module_pinned_source
  source = "git::https://github.com/craigsloggett/terraform-aws-vault-enterprise?ref=9acdcceae57f84fc46e74e25bcb6527e0491c605"

  vault_enterprise_license = var.vault_enterprise_license

  route53_zone = data.aws_route53_zone.vault
  key_pair     = data.aws_key_pair.selected
  ami          = data.aws_ami.selected

  vpc = {
    existing = {
      vpc_id             = data.aws_vpc.selected.id
      private_subnet_ids = data.aws_subnets.private.ids
      public_subnet_ids  = data.aws_subnets.public.ids
    }
  }

  vault_cluster = {
    instance_type = "t3.medium"
    node_count    = 3

    cluster_auto_join_tag = {
      value = data.aws_region.this.region
    }
  }

  vault_pki = {
    intermediate_ca = {
      common_name  = "Vault Intermediate CA"
      country      = "US"
      organization = "HashiCorp Demos"
      key_type     = "ec"
      key_bits     = 384
    }
  }

  nlb = {
    internal          = true
    api_allowed_cidrs = ["0.0.0.0/0"]
  }

  hcp_terraform_jwt_auth = {
    hostname          = "app.terraform.io"
    organization_name = var.hcp_terraform_organization_name
  }
}
