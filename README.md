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

module "vault" {
  # tflint-ignore: terraform_module_pinned_source
  source = "git::https://github.com/craigsloggett/terraform-aws-vault-enterprise"

  project_name             = var.project_name
  route53_zone             = data.aws_route53_zone.vault
  vault_enterprise_license = var.vault_enterprise_license
  ec2_key_pair_name        = var.ec2_key_pair_name
  ec2_ami                  = data.aws_ami.selected

  existing_vpc = {
    vpc_id             = data.aws_vpc.selected.id
    private_subnet_ids = data.aws_subnets.private.ids
    public_subnet_ids  = data.aws_subnets.public.ids
  }

  vault_pki_intermediate_ca = {
    key_type = local.pki_key_type
    key_bits = local.pki_key_bits
  }

  nlb_internal               = true
  vault_api_allowed_cidrs    = ["0.0.0.0/0"]
  vault_server_instance_type = "t3.medium"

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
| <a name="input_bastion_allowed_cidrs"></a> [bastion\_allowed\_cidrs](#input\_bastion\_allowed\_cidrs) | CIDR blocks allowed to SSH to the bastion host. Defaults to 0.0.0.0/0 for convenience; restrict to known ranges in any production deployment. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_bastion_instance_type"></a> [bastion\_instance\_type](#input\_bastion\_instance\_type) | EC2 instance type for the bastion host. | `string` | `"t3.micro"` | no |
| <a name="input_ec2_ami"></a> [ec2\_ami](#input\_ec2\_ami) | AMI to use for EC2 instances. Must be Ubuntu or Debian-based. | <pre>object({<br/>    id   = string<br/>    name = string<br/>  })</pre> | n/a | yes |
| <a name="input_ec2_key_pair_name"></a> [ec2\_key\_pair\_name](#input\_ec2\_key\_pair\_name) | Name of an existing EC2 key pair for SSH access. | `string` | n/a | yes |
| <a name="input_existing_vpc"></a> [existing\_vpc](#input\_existing\_vpc) | Existing VPC to deploy into. When null (default), a new VPC is created.<br/>The existing VPC must already have the required VPC endpoints:<br/>Secrets Manager, KMS, and EC2 (Interface), S3 (Gateway). | <pre>object({<br/>    vpc_id             = string<br/>    private_subnet_ids = list(string)<br/>    public_subnet_ids  = list(string)<br/>  })</pre> | `null` | no |
| <a name="input_hcp_terraform_jwt_auth"></a> [hcp\_terraform\_jwt\_auth](#input\_hcp\_terraform\_jwt\_auth) | Configuration for the HCP Terraform JWT auth method that provides<br/>dynamic, short-lived Vault credentials to HCP Terraform workspaces.<br/>When `organization_name` and `workspace_id` are set, a JWT auth method<br/>is mounted at `mount_path` in the root namespace and configured to<br/>verify tokens against `hostname` via OIDC discovery. A role named<br/>`role_name` is created against that mount with `bound_claims`<br/>restricting authentication to the declared organization and workspace. | <pre>object({<br/>    hostname              = optional(string, "app.terraform.io")<br/>    organization_name     = optional(string, "")<br/>    workspace_id          = optional(string, "")<br/>    oidc_discovery_ca_pem = optional(string, "")<br/>    mount_path            = optional(string, "app-terraform-io")<br/>    role_name             = optional(string, "terraform-admin")<br/>  })</pre> | `{}` | no |
| <a name="input_nlb_internal"></a> [nlb\_internal](#input\_nlb\_internal) | Whether the NLB is internal. | `bool` | `true` | no |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Name prefix for all resources. | `string` | n/a | yes |
| <a name="input_root_volume_size"></a> [root\_volume\_size](#input\_root\_volume\_size) | Size in GiB of the root EBS volume for Vault nodes. | `number` | `50` | no |
| <a name="input_route53_zone"></a> [route53\_zone](#input\_route53\_zone) | Route 53 hosted zone for the Vault DNS record. | <pre>object({<br/>    zone_id = string<br/>    name    = string<br/>  })</pre> | n/a | yes |
| <a name="input_vault_api_allowed_cidrs"></a> [vault\_api\_allowed\_cidrs](#input\_vault\_api\_allowed\_cidrs) | CIDR blocks allowed to reach the Vault API (port 8200) from outside the VPC. Only effective when nlb\_internal is false. | `list(string)` | `[]` | no |
| <a name="input_vault_audit_disk"></a> [vault\_audit\_disk](#input\_vault\_audit\_disk) | EBS configuration for the Vault Audit Log storage volume (/dev/xvdg). | <pre>object({<br/>    volume_type = optional(string, "gp3")<br/>    volume_size = optional(number, 50)<br/>  })</pre> | <pre>{<br/>  "volume_size": 50,<br/>  "volume_type": "gp3"<br/>}</pre> | no |
| <a name="input_vault_aws_auth_role_max_ttl"></a> [vault\_aws\_auth\_role\_max\_ttl](#input\_vault\_aws\_auth\_role\_max\_ttl) | Max TTL for the vault-server AWS auth role. | `string` | `"24h"` | no |
| <a name="input_vault_aws_auth_role_ttl"></a> [vault\_aws\_auth\_role\_ttl](#input\_vault\_aws\_auth\_role\_ttl) | Default TTL for the vault-server AWS auth role. | `string` | `"4h"` | no |
| <a name="input_vault_data_disk"></a> [vault\_data\_disk](#input\_vault\_data\_disk) | EBS configuration for the Vault Raft Data storage volume (/dev/xvdf). | <pre>object({<br/>    volume_type = optional(string, "gp3")<br/>    volume_size = optional(number, 50)<br/>    iops        = optional(number, 3000)<br/>    throughput  = optional(number, 125)<br/>  })</pre> | <pre>{<br/>  "iops": 3000,<br/>  "throughput": 125,<br/>  "volume_size": 50,<br/>  "volume_type": "gp3"<br/>}</pre> | no |
| <a name="input_vault_enterprise_license"></a> [vault\_enterprise\_license](#input\_vault\_enterprise\_license) | Vault Enterprise license string. | `string` | n/a | yes |
| <a name="input_vault_jwt_auth_role_max_ttl"></a> [vault\_jwt\_auth\_role\_max\_ttl](#input\_vault\_jwt\_auth\_role\_max\_ttl) | Max TTL for the HCP Terraform JWT auth role. | `string` | `"2h"` | no |
| <a name="input_vault_jwt_auth_role_ttl"></a> [vault\_jwt\_auth\_role\_ttl](#input\_vault\_jwt\_auth\_role\_ttl) | Default TTL for the HCP Terraform JWT auth role. | `string` | `"1h"` | no |
| <a name="input_vault_node_count"></a> [vault\_node\_count](#input\_vault\_node\_count) | Number of Vault nodes in the cluster. Must be 3 or 5 for Raft quorum. | `number` | `3` | no |
| <a name="input_vault_pki_intermediate_ca"></a> [vault\_pki\_intermediate\_ca](#input\_vault\_pki\_intermediate\_ca) | Configuration for the Vault PKI intermediate CA certificate. | <pre>object({<br/>    common_name  = optional(string, "Vault Intermediate CA")<br/>    country      = optional(string, "")<br/>    organization = optional(string, "")<br/>    key_type     = optional(string, "rsa")<br/>    key_bits     = optional(number, 2048)<br/>  })</pre> | `{}` | no |
| <a name="input_vault_pki_mount_path"></a> [vault\_pki\_mount\_path](#input\_vault\_pki\_mount\_path) | Mount path for the Vault PKI secrets engine used to issue Vault server TLS certificates. | `string` | `"pki_vault"` | no |
| <a name="input_vault_pki_server_cert_ttl"></a> [vault\_pki\_server\_cert\_ttl](#input\_vault\_pki\_server\_cert\_ttl) | TTL requested when the bootstrap script issues the Vault server certificate. | `string` | `"24h"` | no |
| <a name="input_vault_pki_signed_intermediate_wait_timeout_seconds"></a> [vault\_pki\_signed\_intermediate\_wait\_timeout\_seconds](#input\_vault\_pki\_signed\_intermediate\_wait\_timeout\_seconds) | Maximum seconds the bootstrap node waits for the signed intermediate certificate to appear in Secrets Manager. | `number` | `1800` | no |
| <a name="input_vault_pki_vault_mount_max_ttl"></a> [vault\_pki\_vault\_mount\_max\_ttl](#input\_vault\_pki\_vault\_mount\_max\_ttl) | Max lease TTL for the Vault PKI secrets engine mount. | `string` | `"26280h"` | no |
| <a name="input_vault_pki_vault_server_role_max_ttl"></a> [vault\_pki\_vault\_server\_role\_max\_ttl](#input\_vault\_pki\_vault\_server\_role\_max\_ttl) | Max TTL for certificates issued by the vault-server PKI role. | `string` | `"24h"` | no |
| <a name="input_vault_server_iam_resource_names"></a> [vault\_server\_iam\_resource\_names](#input\_vault\_server\_iam\_resource\_names) | Names for the IAM resources created by this module. Each field is optional;<br/>consumers are expected to set these to environment-appropriate values to<br/>avoid collisions when deploying multiple instances of the module into the<br/>same AWS account. Switching a name (or accepting a new default) replaces<br/>the underlying AWS resource since IAM resource names are immutable. | <pre>object({<br/>    role                              = optional(string, "VaultServerRole")<br/>    instance_profile                  = optional(string, "VaultServerInstanceProfile")<br/>    kms_read_write_policy             = optional(string, "KMSReadWriteAccess")<br/>    kms_describe_policy               = optional(string, "KMSDescribeAccess")<br/>    secrets_manager_read_policy       = optional(string, "SecretsManagerReadAccess")<br/>    secrets_manager_describe_policy   = optional(string, "SecretsManagerDescribeAccess")<br/>    secrets_manager_read_write_policy = optional(string, "SecretsManagerReadWriteAccess")<br/>    s3_read_write_policy              = optional(string, "S3ObjectReadWriteAccess")<br/>    s3_list_policy                    = optional(string, "S3BucketListAccess")<br/>    ec2_describe_policy               = optional(string, "EC2DescribeAccess")<br/>    ssm_read_write_policy             = optional(string, "SSMReadWriteAccess")<br/>    iam_read_policy                   = optional(string, "IAMReadAccess")<br/>  })</pre> | `{}` | no |
| <a name="input_vault_server_instance_type"></a> [vault\_server\_instance\_type](#input\_vault\_server\_instance\_type) | EC2 instance type for Vault server nodes. | `string` | `"m5.large"` | no |
| <a name="input_vault_snapshot_interval"></a> [vault\_snapshot\_interval](#input\_vault\_snapshot\_interval) | Seconds between automated Raft snapshots. | `number` | `3600` | no |
| <a name="input_vault_snapshot_retain"></a> [vault\_snapshot\_retain](#input\_vault\_snapshot\_retain) | Number of automated Raft snapshots to retain in S3. | `number` | `72` | no |
| <a name="input_vault_subdomain"></a> [vault\_subdomain](#input\_vault\_subdomain) | Subdomain for the Vault DNS record. | `string` | `"vault"` | no |
| <a name="input_vault_version"></a> [vault\_version](#input\_vault\_version) | Vault Enterprise release version (e.g., 1.21.4+ent). | `string` | `"1.21.4+ent"` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR block for the VPC. | `string` | `"10.0.0.0/16"` | no |
| <a name="input_vpc_private_subnets"></a> [vpc\_private\_subnets](#input\_vpc\_private\_subnets) | Private subnet CIDR blocks. | `list(string)` | <pre>[<br/>  "10.0.1.0/24",<br/>  "10.0.2.0/24",<br/>  "10.0.3.0/24"<br/>]</pre> | no |
| <a name="input_vpc_public_subnets"></a> [vpc\_public\_subnets](#input\_vpc\_public\_subnets) | Public subnet CIDR blocks. | `list(string)` | <pre>[<br/>  "10.0.101.0/24",<br/>  "10.0.102.0/24",<br/>  "10.0.103.0/24"<br/>]</pre> | no |

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
| [aws_iam_role_policy.vault_server_s3_list](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.vault_server_s3_read_write](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
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
| [aws_iam_policy_document.vault_server_s3_list](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.vault_server_s3_read_write](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
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
