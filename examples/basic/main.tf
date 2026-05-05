data "aws_region" "this" {}

locals {
  existing_vpc_name = "hashistack"
}

data "aws_vpc" "selected" {
  filter {
    name   = "tag:Name"
    values = [local.existing_vpc_name]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
  filter {
    name   = "tag:Name"
    values = ["${local.existing_vpc_name}-private-*"]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
  filter {
    name   = "tag:Name"
    values = ["${local.existing_vpc_name}-public-*"]
  }
}

data "aws_route53_zone" "vault" {
  name = "craig-sloggett.sbx.hashidemos.io"
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
    organization_name = "craigsloggett-lab"
  }
}

# TLS Signing Orchestration

## Root CA

resource "tls_private_key" "root_ca" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

resource "tls_self_signed_cert" "root_ca" {
  private_key_pem = tls_private_key.root_ca.private_key_pem

  subject {
    common_name  = "Vault Root CA"
    country      = "US"
    organization = "HashiCorp Demos"
  }

  validity_period_hours = 87600
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

## Intermediate CA Signing

resource "terraform_data" "wait_for_csr" {
  input = module.vault.vault_pki_intermediate_ca_csr_ssm_parameter_name

  provisioner "local-exec" {
    command = "${path.module}/files/wait-for-csr.sh"
    environment = {
      PARAMETER_NAME = self.input
      TIMEOUT_SEC    = "1800"
      REGION         = data.aws_region.this.region
    }
  }
}

data "aws_ssm_parameter" "vault_pki_intermediate_ca_csr" {
  name = module.vault.vault_pki_intermediate_ca_csr_ssm_parameter_name

  depends_on = [terraform_data.wait_for_csr]
}

resource "tls_locally_signed_cert" "vault_pki_signed_intermediate_ca" {
  cert_request_pem   = data.aws_ssm_parameter.vault_pki_intermediate_ca_csr.value
  ca_private_key_pem = tls_private_key.root_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.root_ca.cert_pem

  validity_period_hours = 26280
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

resource "aws_secretsmanager_secret_version" "vault_pki_signed_intermediate_ca" {
  secret_id = module.vault.vault_pki_signed_intermediate_ca_secret_arn
  secret_string = jsonencode({
    certificate = tls_locally_signed_cert.vault_pki_signed_intermediate_ca.cert_pem
    ca_chain    = tls_self_signed_cert.root_ca.cert_pem
  })
}
