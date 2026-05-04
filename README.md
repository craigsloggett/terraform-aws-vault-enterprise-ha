# HashiCorp Vault Enterprise Terraform Module

Terraform module which deploys a Vault Enterprise cluster on AWS with Raft integrated storage and Vault PKI-managed TLS.

## Architecture

- 3 (or 5) Vault nodes across separate availability zones, each with dedicated EBS volumes for Raft storage and audit logs
- AWS KMS auto-unseal
- Raft auto-join via EC2 tag discovery
- Automated cluster initialization with root token and recovery keys stored in Secrets Manager
- PKI intermediate CA with externally signed CSR
- Vault generates the CSR, an external CA signs it, and the signed certificate is imported automatically
- Vault Agent for automated TLS certificate rotation using PKI-signed certificates
- NLB with TCP passthrough (TLS terminates on the Vault nodes), internal by default
- Route 53 DNS alias to the NLB
- Bootstrap TLS certificates and Vault Enterprise license stored in AWS Secrets Manager
- SSM Parameter Store for cluster and PKI state coordination
- Bastion host for SSH access to the private Vault nodes
- VPC endpoints for EC2, KMS, Secrets Manager, and S3
- AWS IAM auth method for Vault Agent authentication
- Optional HCP Terraform JWT auth method for Terraform-managed Vault administration

## Prerequisites

- A Route 53 hosted zone
- A Vault Enterprise license
- An EC2 key pair
- An Ubuntu or Debian-based AMI
- An external CA capable of signing the Vault PKI intermediate CSR (see [PKI intermediate CA](#pki-intermediate-ca))

## Post-deployment

After `terraform apply`, the cluster bootstraps automatically:

1. The bootstrap node initializes the cluster (`vault operator init`), stores the root token and recovery keys in Secrets Manager, and marks the cluster as ready in SSM.
2. Remaining nodes auto-join via Raft and auto-unseal via KMS.
3. The bootstrap node enables the Vault PKI secrets engine, generates an intermediate CA CSR, and publishes it to SSM. It then waits for an external process to sign the CSR and store the signed certificate in Secrets Manager.
4. Once the signed certificate is available, all nodes issue PKI-signed server certificates and Vault Agent begins automated TLS rotation.

Retrieve the root token after deployment (the secret name is prefixed with
`<project-name>-vault-bootstrap-root-token-`):

```bash
aws secretsmanager list-secrets \
  --filter Key=name,Values=<project-name>-vault-bootstrap-root-token \
  --query "SecretList[0].ARN" --output text \
| xargs -I{} aws secretsmanager get-secret-value \
  --secret-id {} --query SecretString --output text
```

## PKI intermediate CA

This module uses a signed CSR pattern for the Vault PKI intermediate CA. During bootstrap, Vault generates a CSR internally (the private key never leaves Vault) and publishes it to SSM. An external process must sign the CSR and store the result in Secrets Manager before the cluster can complete its PKI setup.

The workflow:

1. Vault publishes the intermediate CA CSR to the SSM parameter named in the `vault_pki_intermediate_ca_csr_ssm_parameter_name` output.
2. An external process reads the CSR, signs it with a root or intermediate CA, and writes the signed certificate to the Secrets Manager secret identified by the `vault_pki_intermediate_ca_signed_csr_secret_arn` output. The secret value must be a JSON object:

   ```json
   {
     "certificate": "<signed-intermediate-cert-pem>",
     "ca_chain": "<root-and-intermediate-ca-chain-pem>"
   }
   ```

3. Vault imports the signed certificate, publishes the CA bundle to SSM, issues PKI-signed server certificates, and starts Vault Agent for ongoing TLS rotation.

The bootstrap node waits up to `vault_pki_signed_intermediate_wait_timeout_seconds` (default 1800) for the signed certificate to appear.

See [`examples/basic/`](examples/basic/) for a reference implementation that uses a Terraform-managed root CA to sign the CSR automatically.

## Cluster access

After the PKI bootstrap completes, the TLS CA bundle is published to SSM. Retrieve it using the parameter name from the `vault_tls_ca_bundle_ssm_parameter_name` output:

```bash
aws ssm get-parameter \
  --name "$(terraform output -raw vault_tls_ca_bundle_ssm_parameter_name)" \
  --query "Parameter.Value" --output text > vault-ca.crt

export VAULT_ADDR="$(terraform output -raw vault_url)"
export VAULT_CACERT=vault-ca.crt
vault status
```

## Network access

By default, the NLB is internal and the Vault API is only reachable from within
the VPC. Access the cluster through the bastion host or a VPN connection.

To expose the Vault UI and API over the public internet, set `nlb_internal` to
`false` and provide the CIDR blocks that should be allowed to reach port 8200:

```hcl
module "vault" {
  # ...

  nlb_internal            = false
  vault_api_allowed_cidrs = ["0.0.0.0/0"]
}
```

This places the NLB in the public subnets and adds security group rules for the
specified CIDRs. The Vault nodes remain in private subnets, only the NLB is
internet-facing. Restrict `vault_api_allowed_cidrs` to known ranges where
possible.

## Security Considerations

The Terraform `tls` provider stores bootstrap private key material (CA and
server keys) in state as plaintext. These bootstrap certificates are short-lived
(minutes) and are replaced by Vault PKI-signed certificates during the bootstrap
process. Ensure your state backend is encrypted (e.g., S3 with SSE).

All nodes share a single bootstrap server certificate. This works because the
certificate's `dns_names` includes the cluster FQDN, which Raft uses for
`leader_tls_servername` during auto-join. After PKI bootstrap, each node
receives its own PKI-signed certificate rotated automatically by Vault Agent.

<!-- BEGIN_TF_DOCS -->
## Usage

### main.tf
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

data "aws_route53_zone" "vault" {
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

data "aws_key_pair" "selected" {
  key_name = var.ec2_key_pair_name
}

module "vault" {
  # tflint-ignore: terraform_module_pinned_source
  source = "git::https://github.com/craigsloggett/terraform-aws-vault-enterprise"

  project_name             = var.project_name
  route53_zone             = data.aws_route53_zone.vault
  vault_enterprise_license = var.vault_enterprise_license
  key_pair                 = data.aws_key_pair.selected
  ami                      = data.aws_ami.selected

  vpc = {
    existing = {
      vpc_id             = data.aws_vpc.selected.id
      private_subnet_ids = data.aws_subnets.private.ids
      public_subnet_ids  = data.aws_subnets.public.ids
    }
  }

  vault_pki = {
    intermediate_ca = {
      key_type = local.pki_key_type
      key_bits = local.pki_key_bits
    }
  }

  nlb = {
    internal          = true
    api_allowed_cidrs = ["0.0.0.0/0"]
  }

  vault_enterprise_servers = {
    instance_type = "t3.medium"
    cluster_auto_join_tag = {
      value = var.project_name
    }
  }

  hcp_terraform_jwt_auth = {
    hostname          = "app.terraform.io"
    organization_name = var.hcp_terraform_organization_name
  }
}
```

## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | ~> 4.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | ~> 4.0 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_ami"></a> [ami](#input\_ami) | AMI for EC2 instances. Must be Ubuntu or Debian-based. Accepts the result of an aws\_ami data source directly. | <pre>object({<br/>    id   = string<br/>    name = string<br/>  })</pre> | n/a | yes |
| <a name="input_bastion"></a> [bastion](#input\_bastion) | Bastion host configuration. `allowed_cidrs` defaults to 0.0.0.0/0 for lab<br/>convenience; restrict to known ranges in any production deployment. | <pre>object({<br/>    name          = optional(string, "vault-enterprise-bastion-host")<br/>    instance_type = optional(string, "t3.micro")<br/>    allowed_cidrs = optional(list(string), ["0.0.0.0/0"])<br/>  })</pre> | `{}` | no |
| <a name="input_hcp_terraform_jwt_auth"></a> [hcp\_terraform\_jwt\_auth](#input\_hcp\_terraform\_jwt\_auth) | Configuration for the HCP Terraform JWT auth method that provides<br/>dynamic, short-lived Vault credentials to HCP Terraform workspaces.<br/>When `organization_name` and `workspace_id` are set, a JWT auth method<br/>is mounted at `mount_path` in the root namespace and configured to<br/>verify tokens against `hostname` via OIDC discovery. A role named<br/>`role_name` is created against that mount with `bound_claims`<br/>restricting authentication to the declared organization and workspace. | <pre>object({<br/>    hostname              = optional(string, "app.terraform.io")<br/>    organization_name     = optional(string, "")<br/>    workspace_id          = optional(string, "")<br/>    oidc_discovery_ca_pem = optional(string, "")<br/>    mount_path            = optional(string, "app-terraform-io")<br/>    role_name             = optional(string, "terraform-admin")<br/>  })</pre> | `{}` | no |
| <a name="input_iam_instance_profile"></a> [iam\_instance\_profile](#input\_iam\_instance\_profile) | IAM instance profile configuration for the Vault Enterprise EC2 instances.<br/>The module creates one instance profile and associates it with the IAM role<br/>created by this module. Defaults reflect the module's recommended PascalCase<br/>naming; consumer-supplied values are passed through verbatim with no<br/>transformation. | <pre>object({<br/>    name = optional(string, "VaultEnterpriseServerInstanceProfile")<br/>    path = optional(string, "/")<br/>  })</pre> | `{}` | no |
| <a name="input_iam_role"></a> [iam\_role](#input\_iam\_role) | IAM role configuration for the Vault Enterprise EC2 instances. The module<br/>creates one role with several inline policies attached. Defaults reflect the<br/>module's recommended PascalCase naming; consumer-supplied values are passed<br/>through verbatim with no transformation. | <pre>object({<br/>    name = optional(string, "VaultEnterpriseServerRole")<br/>    path = optional(string, "/")<br/>    inline_policy_names = optional(object({<br/>      kms_read_write             = optional(string, "KMSReadWriteAccess")<br/>      kms_describe               = optional(string, "KMSDescribeAccess")<br/>      secrets_manager_read       = optional(string, "SecretsManagerReadAccess")<br/>      secrets_manager_describe   = optional(string, "SecretsManagerDescribeAccess")<br/>      secrets_manager_read_write = optional(string, "SecretsManagerReadWriteAccess")<br/>      s3_object_read_write       = optional(string, "S3ObjectReadWriteAccess")<br/>      s3_bucket_list             = optional(string, "S3BucketListAccess")<br/>      ec2_describe               = optional(string, "EC2DescribeAccess")<br/>      ssm_read_write             = optional(string, "SSMReadWriteAccess")<br/>      iam_read                   = optional(string, "IAMReadAccess")<br/>    }), {})<br/>  })</pre> | `{}` | no |
| <a name="input_key_pair"></a> [key\_pair](#input\_key\_pair) | EC2 key pair for SSH access. Accepts the result of an aws\_key\_pair data source directly. | <pre>object({<br/>    key_name = string<br/>  })</pre> | n/a | yes |
| <a name="input_kms_key"></a> [kms\_key](#input\_kms\_key) | Configuration for the KMS key used for Vault auto-unseal. | <pre>object({<br/>    name = optional(string, "vault-enterprise-auto-unseal-key")<br/>  })</pre> | `{}` | no |
| <a name="input_nlb"></a> [nlb](#input\_nlb) | NLB configuration for the Vault API. `api_allowed_cidrs` is only effective<br/>when `internal` is false. | <pre>object({<br/>    internal          = optional(bool, true)<br/>    api_allowed_cidrs = optional(list(string), [])<br/>  })</pre> | `{}` | no |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Name prefix for all resources. | `string` | n/a | yes |
| <a name="input_route53_record"></a> [route53\_record](#input\_route53\_record) | Route 53 A record configuration. The record is created in the hosted zone<br/>supplied via `route53_zone` and points (via alias) at the NLB created by<br/>this module. The record's fully-qualified name is<br/>`${subdomain}.${route53_zone.name}`. | <pre>object({<br/>    subdomain = optional(string, "vault")<br/>  })</pre> | `{}` | no |
| <a name="input_route53_zone"></a> [route53\_zone](#input\_route53\_zone) | Route 53 hosted zone for the Vault DNS record. Accepts the result of an aws\_route53\_zone data source directly. | <pre>object({<br/>    zone_id = string<br/>    name    = string<br/>  })</pre> | n/a | yes |
| <a name="input_security_groups"></a> [security\_groups](#input\_security\_groups) | Name prefixes for the security groups created by this module. The AWS<br/>provider appends a random suffix to guarantee uniqueness, which enables<br/>create\_before\_destroy for security group replacements. | <pre>object({<br/>    bastion_name_prefix       = optional(string, "vault-enterprise-bastion-sg-")<br/>    vault_servers_name_prefix = optional(string, "vault-enterprise-servers-sg-")<br/>    vpc_endpoints_name_prefix = optional(string, "vault-enterprise-vpc-endpoints-sg-")<br/>  })</pre> | `{}` | no |
| <a name="input_vault"></a> [vault](#input\_vault) | Vault Enterprise product configuration. | <pre>object({<br/>    enterprise_version = optional(string, "1.21.4+ent")<br/>    cluster_name       = optional(string, "vault-enterprise")<br/>  })</pre> | `{}` | no |
| <a name="input_vault_auth"></a> [vault\_auth](#input\_vault\_auth) | TTL configuration for Vault auth method roles. `vault_auth.aws` configures<br/>Vault's AWS auth method (Vault authenticating callers via AWS IAM identities)<br/>and is unrelated to the `iam_role` variable, which configures the AWS IAM<br/>role used by the EC2 instances running Vault. | <pre>object({<br/>    aws = optional(object({<br/>      role_ttl     = optional(string, "4h")<br/>      role_max_ttl = optional(string, "24h")<br/>    }), {})<br/>    jwt = optional(object({<br/>      role_ttl     = optional(string, "1h")<br/>      role_max_ttl = optional(string, "2h")<br/>    }), {})<br/>  })</pre> | `{}` | no |
| <a name="input_vault_enterprise_license"></a> [vault\_enterprise\_license](#input\_vault\_enterprise\_license) | Vault Enterprise license string. | `string` | n/a | yes |
| <a name="input_vault_enterprise_servers"></a> [vault\_enterprise\_servers](#input\_vault\_enterprise\_servers) | Configuration for the Vault Enterprise server EC2 instances and their EBS volumes. | <pre>object({<br/>    instance_name    = optional(string, "vault-enterprise-server")<br/>    volume_name      = optional(string, "vault-enterprise-server-volume")<br/>    instance_type    = optional(string, "m5.large")<br/>    node_count       = optional(number, 3)<br/>    root_volume_size = optional(number, 50)<br/>    raft_data_disk = optional(object({<br/>      volume_type = optional(string, "gp3")<br/>      volume_size = optional(number, 50)<br/>      iops        = optional(number, 3000)<br/>      throughput  = optional(number, 125)<br/>    }), {})<br/>    audit_disk = optional(object({<br/>      volume_type = optional(string, "gp3")<br/>      volume_size = optional(number, 50)<br/>    }), {})<br/>    cluster_auto_join_tag = object({<br/>      key   = optional(string, "vault:raft:retryjoin:autojoin")<br/>      value = string<br/>    })<br/>  })</pre> | n/a | yes |
| <a name="input_vault_pki"></a> [vault\_pki](#input\_vault\_pki) | Vault PKI secrets engine configuration. | <pre>object({<br/>    mount_path = optional(string, "pki_vault")<br/>    intermediate_ca = optional(object({<br/>      common_name  = optional(string, "Vault Intermediate CA")<br/>      country      = optional(string, "")<br/>      organization = optional(string, "")<br/>      key_type     = optional(string, "rsa")<br/>      key_bits     = optional(number, 2048)<br/>    }), {})<br/>    mount_max_ttl                         = optional(string, "26280h")<br/>    server_role_max_ttl                   = optional(string, "24h")<br/>    server_cert_ttl                       = optional(string, "24h")<br/>    signed_intermediate_wait_timeout_secs = optional(number, 1800)<br/>  })</pre> | `{}` | no |
| <a name="input_vault_snapshots"></a> [vault\_snapshots](#input\_vault\_snapshots) | Vault Raft snapshot configuration. The module creates an S3 bucket for<br/>snapshot storage; bucket configuration beyond `name` is derived from the<br/>module's other inputs (KMS key, VPC, etc.) and is not exposed. Note that<br/>S3 bucket names are globally unique across all AWS accounts; consumers<br/>deploying multiple instances of this module must override the default. | <pre>object({<br/>    interval      = optional(number, 3600)<br/>    retain        = optional(number, 72)<br/>    aws_s3_bucket = optional(string, "vault-enterprise-snapshots")<br/>  })</pre> | `{}` | no |
| <a name="input_vpc"></a> [vpc](#input\_vpc) | VPC configuration. When `existing` is null (default), a new VPC is created<br/>using `cidr`, `private_subnets`, and `public_subnets`. When `existing` is<br/>set, those creation fields are ignored and the supplied VPC is used; it<br/>must already have the required VPC endpoints (Secrets Manager, KMS, EC2<br/>Interface; S3 Gateway). | <pre>object({<br/>    name            = optional(string, "vault-enterprise-vpc")<br/>    cidr            = optional(string, "10.0.0.0/16")<br/>    private_subnets = optional(list(string), ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"])<br/>    public_subnets  = optional(list(string), ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"])<br/>    existing = optional(object({<br/>      vpc_id             = string<br/>      private_subnet_ids = list(string)<br/>      public_subnet_ids  = list(string)<br/>    }), null)<br/>  })</pre> | `{}` | no |
| <a name="input_vpc_endpoints"></a> [vpc\_endpoints](#input\_vpc\_endpoints) | Configuration for the VPC endpoints created by this module (Secrets Manager,<br/>KMS, EC2 Interface, S3 Gateway). Only created when `vpc.existing` is null;<br/>when using an existing VPC, endpoints must be provisioned separately. | <pre>object({<br/>    secretsmanager_name = optional(string, "vault-enterprise-secretsmanager-vpc-endpoint")<br/>    kms_name            = optional(string, "vault-enterprise-kms-vpc-endpoint")<br/>    ec2_name            = optional(string, "vault-enterprise-ec2-vpc-endpoint")<br/>    s3_name             = optional(string, "vault-enterprise-s3-vpc-endpoint")<br/>  })</pre> | `{}` | no |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_autoscaling_group.vault](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group) | resource |
| [aws_iam_instance_profile.vault_server](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.vault_server](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.vault_server_ec2_describe](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.vault_server_iam_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.vault_server_kms_describe](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.vault_server_kms_read_write](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.vault_server_s3_bucket_list](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.vault_server_s3_object_read_write](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.vault_server_secrets_manager_describe](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.vault_server_secrets_manager_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.vault_server_secrets_manager_read_write](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.vault_server_ssm_read_write](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_instance.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_kms_alias.vault](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.vault](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_launch_template.vault](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_lb.vault](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.vault](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_target_group.vault](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_route53_record.vault](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_s3_bucket.vault_snapshots](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.vault_snapshots](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_policy.vault_snapshots](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.vault_snapshots](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.vault_snapshots](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.vault_snapshots](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_secretsmanager_secret.bootstrap_tls_ca](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.bootstrap_tls_cert](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.bootstrap_tls_private_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.vault_enterprise_license](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.vault_pki_intermediate_ca_signed_csr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.vault_recovery_keys](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.vault_server_bootstrap_root_token](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.bootstrap_tls_ca](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.bootstrap_tls_cert](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.bootstrap_tls_private_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.vault_enterprise_license](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_security_group.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.vault](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.vpc_endpoints](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_ssm_parameter.vault_cluster_state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.vault_pki_intermediate_ca_csr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.vault_pki_state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.vault_tls_ca_bundle](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_vpc_endpoint.ec2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.kms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.secretsmanager](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_security_group_egress_rule.bastion_all](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.vault_all](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.bastion_ssh](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.vault_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.vault_api_external](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.vault_cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.vault_ssh](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.vpc_endpoints_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [tls_cert_request.bootstrap_tls_cert_request](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/cert_request) | resource |
| [tls_locally_signed_cert.bootstrap_tls_cert](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/locally_signed_cert) | resource |
| [tls_private_key.bootstrap_tls_ca_private_key](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [tls_private_key.bootstrap_tls_private_key](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [tls_self_signed_cert.bootstrap_tls_ca](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/self_signed_cert) | resource |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.vault_server_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.vault_server_ec2_describe](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.vault_server_iam_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.vault_server_kms_describe](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.vault_server_kms_read_write](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.vault_server_s3_bucket_list](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.vault_server_s3_object_read_write](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.vault_server_secrets_manager_describe](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.vault_server_secrets_manager_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.vault_server_secrets_manager_read_write](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.vault_server_ssm_read_write](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.vault_snapshots](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_vpc.existing](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bastion_public_ip"></a> [bastion\_public\_ip](#output\_bastion\_public\_ip) | Public IP of the bastion host. |
| <a name="output_ec2_ami_name"></a> [ec2\_ami\_name](#output\_ec2\_ami\_name) | Name of the AMI used for EC2 instances. |
| <a name="output_vault_asg_name"></a> [vault\_asg\_name](#output\_vault\_asg\_name) | Name of the Vault Auto Scaling Group. |
| <a name="output_vault_iam_role_name"></a> [vault\_iam\_role\_name](#output\_vault\_iam\_role\_name) | Name of the Vault server IAM role. |
| <a name="output_vault_jwt_auth_path"></a> [vault\_jwt\_auth\_path](#output\_vault\_jwt\_auth\_path) | Vault JWT auth method path for HCP Terraform (TFC\_VAULT\_AUTH\_PATH). |
| <a name="output_vault_jwt_auth_role_name"></a> [vault\_jwt\_auth\_role\_name](#output\_vault\_jwt\_auth\_role\_name) | Vault JWT auth role name for HCP Terraform (TFC\_VAULT\_RUN\_ROLE). |
| <a name="output_vault_kms_key_id"></a> [vault\_kms\_key\_id](#output\_vault\_kms\_key\_id) | KMS key ID used for Vault auto-unseal. |
| <a name="output_vault_pki_intermediate_ca_csr_ssm_parameter_name"></a> [vault\_pki\_intermediate\_ca\_csr\_ssm\_parameter\_name](#output\_vault\_pki\_intermediate\_ca\_csr\_ssm\_parameter\_name) | SSM parameter name where the intermediate CA CSR is published. |
| <a name="output_vault_pki_intermediate_ca_signed_csr_secret_arn"></a> [vault\_pki\_intermediate\_ca\_signed\_csr\_secret\_arn](#output\_vault\_pki\_intermediate\_ca\_signed\_csr\_secret\_arn) | Secrets Manager ARN for the signed CSR and root CA PEM. |
| <a name="output_vault_snapshots_bucket"></a> [vault\_snapshots\_bucket](#output\_vault\_snapshots\_bucket) | S3 bucket for Vault snapshots. |
| <a name="output_vault_target_group_arn"></a> [vault\_target\_group\_arn](#output\_vault\_target\_group\_arn) | ARN of the Vault NLB target group. |
| <a name="output_vault_tls_ca_bundle_ssm_parameter_name"></a> [vault\_tls\_ca\_bundle\_ssm\_parameter\_name](#output\_vault\_tls\_ca\_bundle\_ssm\_parameter\_name) | SSM Parameter for the Vault PKI managed TLS CA bundle. |
| <a name="output_vault_url"></a> [vault\_url](#output\_vault\_url) | URL of the Vault cluster. |
| <a name="output_vault_version"></a> [vault\_version](#output\_vault\_version) | Vault Enterprise version deployed. |
<!-- END_TF_DOCS -->
