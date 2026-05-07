# HashiCorp Vault Enterprise Terraform Module

Terraform module which deploys a Vault Enterprise cluster on AWS with Raft integrated storage and Vault PKI-managed TLS.

<!-- BEGIN_TF_DOCS -->
## Usage

### main.tf
```hcl
data "aws_route53_zone" "selected" {
  name = var.route53_zone_name
}

module "vault" {
  # tflint-ignore: terraform_module_pinned_source
  source = "git::https://github.com/craigsloggett/terraform-aws-vault-enterprise"

  vault_enterprise_license = var.vault_enterprise_license
  route53_zone             = data.aws_route53_zone.selected
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
| <a name="input_ami"></a> [ami](#input\_ami) | AMI for EC2 instances. Must be Ubuntu or Debian-based. Accepts the result of an `aws_ami` data source directly. | <pre>object({<br/>    owners = optional(list(string), ["amazon"])<br/>    name   = optional(string, "ubuntu/images/hvm-ssd-gp3/ubuntu-resolute-26.04-amd64-server-20260503")<br/>  })</pre> | `{}` | no |
| <a name="input_bastion"></a> [bastion](#input\_bastion) | Bastion host configuration. `allowed_cidrs` defaults to `["0.0.0.0/0"]` for<br/>convenience; restrict to known ranges in any production deployment. | <pre>object({<br/>    name          = optional(string, "vault-enterprise-bastion-host")<br/>    instance_type = optional(string, "t3.micro")<br/>    allowed_cidrs = optional(list(string), ["0.0.0.0/0"])<br/><br/>    security_group = optional(object({<br/>      name_prefix = optional(string, "vault-enterprise-bastion-host-")<br/>      name        = optional(string, "vault-enterprise-bastion-host")<br/>    }), {})<br/>  })</pre> | `{}` | no |
| <a name="input_bootstrap"></a> [bootstrap](#input\_bootstrap) | AWS resources used only during the Vault bootstrap ceremony. Secrets Manager<br/>secrets hold ephemeral bootstrap TLS material that Vault-issued certificates<br/>replace post-bootstrap; SSM parameters hold non-sensitive coordination state<br/>and the intermediate CA CSR exchanged out-of-band. | <pre>object({<br/>    secretsmanager_secret = optional(object({<br/>      tls_ca_name_prefix          = optional(string, "vault-enterprise-bootstrap-tls-ca-")<br/>      tls_cert_name_prefix        = optional(string, "vault-enterprise-bootstrap-tls-cert-")<br/>      tls_private_key_name_prefix = optional(string, "vault-enterprise-bootstrap-tls-private-key-")<br/>    }), {})<br/><br/>    ssm_parameter = optional(object({<br/>      cluster_state_name = optional(string, "/vault-enterprise/bootstrap/cluster/state")<br/>      pki_state_name     = optional(string, "/vault-enterprise/bootstrap/pki/state")<br/>    }), {})<br/>  })</pre> | `{}` | no |
| <a name="input_hcp_terraform_jwt_auth"></a> [hcp\_terraform\_jwt\_auth](#input\_hcp\_terraform\_jwt\_auth) | Configuration for the HCP Terraform JWT auth method that provides<br/>dynamic, short-lived Vault credentials to HCP Terraform workspaces.<br/>When `organization_name` and `workspace_id` are set, a JWT auth method<br/>is mounted at `mount_path` in the root namespace and configured to<br/>verify tokens against `hostname` via OIDC discovery. A role named<br/>`role_name` is created against that mount with `bound_claims`<br/>restricting authentication to the declared organization and workspace. | <pre>object({<br/>    hostname              = optional(string, "app.terraform.io")<br/>    organization_name     = optional(string, "")<br/>    workspace_id          = optional(string, "")<br/>    oidc_discovery_ca_pem = optional(string, "")<br/>    mount_path            = optional(string, "app-terraform-io")<br/>    role_name             = optional(string, "hcp-terraform")<br/>  })</pre> | `{}` | no |
| <a name="input_iam_role"></a> [iam\_role](#input\_iam\_role) | IAM role configuration for the Vault Enterprise EC2 instances. The module<br/>creates one role with several inline policies attached and an associated<br/>instance profile. | <pre>object({<br/>    name = optional(string, "VaultEnterpriseServerRole")<br/>    path = optional(string, "/")<br/><br/>    instance_profile = optional(object({<br/>      name = optional(string, "VaultEnterpriseServerInstanceProfile")<br/>      path = optional(string, "/")<br/>    }), {})<br/><br/>    inline_policy_names = optional(object({<br/>      kms_read_write             = optional(string, "KMSReadWriteAccess")<br/>      kms_describe               = optional(string, "KMSDescribeAccess")<br/>      secrets_manager_read       = optional(string, "SecretsManagerReadAccess")<br/>      secrets_manager_describe   = optional(string, "SecretsManagerDescribeAccess")<br/>      secrets_manager_read_write = optional(string, "SecretsManagerReadWriteAccess")<br/>      s3_object_read_write       = optional(string, "S3ObjectReadWriteAccess")<br/>      s3_bucket_list             = optional(string, "S3BucketListAccess")<br/>      ec2_describe               = optional(string, "EC2DescribeAccess")<br/>      ssm_read_write             = optional(string, "SSMReadWriteAccess")<br/>      iam_read                   = optional(string, "IAMReadAccess")<br/>    }), {})<br/>  })</pre> | `{}` | no |
| <a name="input_key_pair"></a> [key\_pair](#input\_key\_pair) | EC2 key pair for SSH access. Accepts the result of an `aws_key_pair` data source directly. | <pre>object({<br/>    key_name = string<br/>  })</pre> | `null` | no |
| <a name="input_kms_key"></a> [kms\_key](#input\_kms\_key) | Configuration for the KMS key used for Vault auto-unseal. | <pre>object({<br/>    name                    = optional(string, "vault-enterprise-auto-unseal-key")<br/>    alias                   = optional(string, "vault-enterprise-auto-unseal-key")<br/>    deletion_window_in_days = optional(number, 7)<br/>    enable_key_rotation     = optional(bool, true)<br/>  })</pre> | `{}` | no |
| <a name="input_nlb"></a> [nlb](#input\_nlb) | NLB configuration for the Vault API. `api_allowed_cidrs` is only effective<br/>when `internal` is `false`. | <pre>object({<br/>    name_prefix       = optional(string, "vault-")<br/>    internal          = optional(bool, true)<br/>    api_allowed_cidrs = optional(list(string), [])<br/><br/>    lb_target_group = optional(object({<br/>      name_prefix = optional(string, "vault-")<br/>    }), {})<br/>  })</pre> | `{}` | no |
| <a name="input_route53_record"></a> [route53\_record](#input\_route53\_record) | Route53 A record configuration. The record is created in the hosted zone<br/>supplied via `route53_zone` and points (via alias) at the NLB created by<br/>this module. | <pre>object({<br/>    subdomain = optional(string, "vault")<br/>  })</pre> | `{}` | no |
| <a name="input_route53_zone"></a> [route53\_zone](#input\_route53\_zone) | Route 53 hosted zone for the Vault DNS record. Accepts the result of an `aws_route53_zone` data source directly. | <pre>object({<br/>    zone_id = string<br/>    name    = string<br/>  })</pre> | n/a | yes |
| <a name="input_vault"></a> [vault](#input\_vault) | Vault Enterprise product configuration. | <pre>object({<br/>    version       = optional(string, "1.21.4+ent")<br/>    ui            = optional(bool, true)<br/>    disable_mlock = optional(bool, true)<br/>    cluster_name  = optional(string, "vault-enterprise")<br/><br/>    log_level  = optional(string, "info")<br/>    log_format = optional(string, "json")<br/><br/>    listener_tcp = optional(object({<br/>      tls_min_version = optional(string, "tls13")<br/>    }), {})<br/><br/>    telemetry = optional(object({<br/>      prometheus_retention_time = optional(string, "24h")<br/>      disable_hostname          = optional(bool, true)<br/>    }), {})<br/><br/>    secretsmanager_secret = optional(object({<br/>      license_name_prefix       = optional(string, "vault-enterprise-license-")<br/>      recovery_keys_name_prefix = optional(string, "vault-enterprise-recovery-keys-")<br/>      root_token_name_prefix    = optional(string, "vault-enterprise-root-token-")<br/>    }), {})<br/>  })</pre> | `{}` | no |
| <a name="input_vault_auth"></a> [vault\_auth](#input\_vault\_auth) | TTL configuration for Vault auth method roles. | <pre>object({<br/>    aws = optional(object({<br/>      role_ttl     = optional(string, "4h")<br/>      role_max_ttl = optional(string, "24h")<br/>    }), {})<br/><br/>    jwt = optional(object({<br/>      role_ttl     = optional(string, "1h")<br/>      role_max_ttl = optional(string, "2h")<br/>    }), {})<br/>  })</pre> | `{}` | no |
| <a name="input_vault_autopilot"></a> [vault\_autopilot](#input\_vault\_autopilot) | Vault Enterprise autopilot configuration. | <pre>object({<br/>    cleanup_dead_servers               = optional(bool, true)<br/>    dead_server_last_contact_threshold = optional(string, "24h")<br/>  })</pre> | `{}` | no |
| <a name="input_vault_cluster"></a> [vault\_cluster](#input\_vault\_cluster) | Configuration for the Vault Enterprise server EC2 instances and their EBS volumes. | <pre>object({<br/>    instance_type    = optional(string, "m5.large")<br/>    node_count       = optional(number, 5)<br/>    root_volume_size = optional(number, 50)<br/><br/>    raft_data_disk = optional(object({<br/>      volume_type = optional(string, "gp3")<br/>      volume_size = optional(number, 50)<br/>      iops        = optional(number, 3000)<br/>      throughput  = optional(number, 125)<br/>    }), {})<br/><br/>    audit_disk = optional(object({<br/>      volume_type = optional(string, "gp3")<br/>      volume_size = optional(number, 50)<br/>    }), {})<br/><br/>    auto_join = optional(object({<br/>      tag_key   = optional(string, "vault:raft:retryjoin:autojoin")<br/>      tag_value = optional(string, "vault-enterprise")<br/>    }), {})<br/><br/>    security_group = optional(object({<br/>      name_prefix = optional(string, "vault-enterprise-servers-")<br/>      name        = optional(string, "vault-enterprise-servers")<br/>    }), {})<br/><br/>    launch_template = optional(object({<br/>      name_prefix = optional(string, "vault-enterprise-servers-")<br/>      volume_name = optional(string, "vault-enterprise-volume")<br/>    }), {})<br/><br/>    autoscaling_group = optional(object({<br/>      name_prefix   = optional(string, "vault-enterprise-servers-")<br/>      instance_name = optional(string, "vault-enterprise-server")<br/>    }), {})<br/>  })</pre> | `{}` | no |
| <a name="input_vault_enterprise_license"></a> [vault\_enterprise\_license](#input\_vault\_enterprise\_license) | Vault Enterprise license string. | `string` | n/a | yes |
| <a name="input_vault_pki"></a> [vault\_pki](#input\_vault\_pki) | Vault PKI secrets engine configuration. | <pre>object({<br/>    mount_path                                = optional(string, "pki_vault")<br/>    mount_max_ttl                             = optional(string, "26280h")<br/>    server_role_max_ttl                       = optional(string, "24h")<br/>    server_cert_ttl                           = optional(string, "24h")<br/>    signed_intermediate_poll_interval_seconds = optional(number, 10)<br/>    signed_intermediate_wait_timeout_seconds  = optional(number, 1800)<br/><br/>    secretsmanager_secret = optional(object({<br/>      signed_intermediate_ca_name_prefix = optional(string, "vault-enterprise-signed-intermediate-ca-")<br/>    }), {})<br/><br/>    ssm_parameter = optional(object({<br/>      intermediate_ca_name     = optional(string, "/vault-enterprise/pki/intermediate-ca")<br/>      intermediate_ca_csr_name = optional(string, "/vault-enterprise/pki/intermediate-ca-csr")<br/>    }), {})<br/><br/>    intermediate_ca = optional(object({<br/>      common_name  = optional(string, "Vault Intermediate CA")<br/>      country      = optional(string, "")<br/>      organization = optional(string, "")<br/>      key_type     = optional(string, "rsa")<br/>      key_bits     = optional(number, 2048)<br/>    }), {})<br/>  })</pre> | `{}` | no |
| <a name="input_vault_snapshot"></a> [vault\_snapshot](#input\_vault\_snapshot) | Vault Enterprise snapshot configuration. | <pre>object({<br/>    aws_s3_bucket = optional(object({<br/>      name_prefix   = optional(string, "vault-enterprise-snapshots-")<br/>      force_destroy = optional(bool, false)<br/>    }), {})<br/>    path_prefix = optional(string, "snapshots/")<br/>    file_prefix = optional(string, "vault-snapshot")<br/>    interval    = optional(number, 3600)<br/>    retain      = optional(number, 72)<br/>  })</pre> | `{}` | no |
| <a name="input_vpc"></a> [vpc](#input\_vpc) | VPC configuration. When `existing` is null (default), a new VPC is created<br/>using `cidr`, `private_subnets`, and `public_subnets`. When `existing` is<br/>set, those creation fields are ignored and the supplied VPC is used. The<br/>supplied VPC must have the required VPC endpoints configured. | <pre>object({<br/>    name            = optional(string, "vault-enterprise-vpc")<br/>    cidr            = optional(string, "10.0.0.0/16")<br/>    private_subnets = optional(list(string), ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"])<br/>    public_subnets  = optional(list(string), ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"])<br/><br/>    existing = optional(object({<br/>      vpc_id             = string<br/>      private_subnet_ids = list(string)<br/>      public_subnet_ids  = list(string)<br/>    }), null)<br/>  })</pre> | `{}` | no |
| <a name="input_vpc_endpoints"></a> [vpc\_endpoints](#input\_vpc\_endpoints) | Configuration for the VPC endpoints created by this module. Only created<br/>when `vpc.existing` is null. | <pre>object({<br/>    secretsmanager_name = optional(string, "vault-enterprise-secretsmanager-vpc-endpoint")<br/>    kms_name            = optional(string, "vault-enterprise-kms-vpc-endpoint")<br/>    ec2_name            = optional(string, "vault-enterprise-ec2-vpc-endpoint")<br/>    s3_name             = optional(string, "vault-enterprise-s3-vpc-endpoint")<br/><br/>    security_group = optional(object({<br/>      name_prefix = optional(string, "vault-enterprise-vpc-endpoints-")<br/>      name        = optional(string, "vault-enterprise-vpc-endpoints")<br/>    }), {})<br/>  })</pre> | `{}` | no |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_autoscaling_group.vault_enterprise](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group) | resource |
| [aws_iam_instance_profile.vault_enterprise](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.vault_enterprise](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.ec2_describe](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.iam_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.kms_describe](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.kms_read_write](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.s3_bucket_list](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.s3_object_read_write](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.secrets_manager_describe](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.secrets_manager_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.secrets_manager_read_write](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ssm_read_write](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_instance.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_kms_alias.auto_unseal](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.auto_unseal](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_launch_template.vault_enterprise](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_lb.vault_enterprise](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.vault_enterprise](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_target_group.vault_enterprise](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_route53_record.vault_enterprise](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_s3_bucket.snapshots](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.snapshots](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_policy.snapshots](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.snapshots](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.snapshots](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.snapshots](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_secretsmanager_secret.bootstrap_tls_ca](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.bootstrap_tls_cert](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.bootstrap_tls_private_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.license](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.recovery_keys](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.root_token](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.vault_pki_signed_intermediate_ca](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.bootstrap_tls_ca](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.bootstrap_tls_cert](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.bootstrap_tls_private_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.license](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_security_group.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.vault_enterprise_servers](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.vpc_endpoints](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_ssm_parameter.bootstrap_cluster_state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.bootstrap_pki_state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.vault_pki_intermediate_ca](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.vault_pki_intermediate_ca_csr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_vpc_endpoint.ec2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.kms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.secretsmanager](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_security_group_egress_rule.bastion_all](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.vault_all](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.bastion_ssh](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.vault_enterprise_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.vault_enterprise_api_external](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.vault_enterprise_cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.vault_ssh](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.vpc_endpoints_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [tls_cert_request.bootstrap_tls_cert_request](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/cert_request) | resource |
| [tls_locally_signed_cert.bootstrap_tls_cert](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/locally_signed_cert) | resource |
| [tls_private_key.bootstrap_tls_ca_private_key](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [tls_private_key.bootstrap_tls_private_key](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [tls_self_signed_cert.bootstrap_tls_ca](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/self_signed_cert) | resource |
| [aws_ami.selected](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.deny_insecure_transport](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ec2_describe](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.iam_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.kms_describe](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.kms_read_write](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.s3_bucket_list](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.s3_object_read_write](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.secrets_manager_describe](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.secrets_manager_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.secrets_manager_read_write](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ssm_read_write](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_vpc.existing](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_ami_name"></a> [ami\_name](#output\_ami\_name) | Name of the AMI used for EC2 instances. |
| <a name="output_bastion_public_ip"></a> [bastion\_public\_ip](#output\_bastion\_public\_ip) | Public IP of the bastion host. |
| <a name="output_bootstrap_cluster_state_ssm_parameter_name"></a> [bootstrap\_cluster\_state\_ssm\_parameter\_name](#output\_bootstrap\_cluster\_state\_ssm\_parameter\_name) | SSM Parameter for the bootstrap initialization state flag. |
| <a name="output_bootstrap_pki_state_ssm_parameter_name"></a> [bootstrap\_pki\_state\_ssm\_parameter\_name](#output\_bootstrap\_pki\_state\_ssm\_parameter\_name) | SSM Parameter for the bootstrap PKI state flag. |
| <a name="output_hcp_terraform_jwt_auth_mount_path"></a> [hcp\_terraform\_jwt\_auth\_mount\_path](#output\_hcp\_terraform\_jwt\_auth\_mount\_path) | Vault JWT auth method path for HCP Terraform (TFC\_VAULT\_AUTH\_PATH). |
| <a name="output_hcp_terraform_jwt_auth_role_name"></a> [hcp\_terraform\_jwt\_auth\_role\_name](#output\_hcp\_terraform\_jwt\_auth\_role\_name) | Vault JWT auth role name for HCP Terraform (TFC\_VAULT\_RUN\_ROLE). |
| <a name="output_vault_cluster_autoscaling_group_name"></a> [vault\_cluster\_autoscaling\_group\_name](#output\_vault\_cluster\_autoscaling\_group\_name) | Name of the Vault Enterprise Auto Scaling Group. |
| <a name="output_vault_pki_intermediate_ca_csr_ssm_parameter_name"></a> [vault\_pki\_intermediate\_ca\_csr\_ssm\_parameter\_name](#output\_vault\_pki\_intermediate\_ca\_csr\_ssm\_parameter\_name) | SSM parameter name where the Vault PKI intermediate CA CSR is published. |
| <a name="output_vault_pki_intermediate_ca_ssm_parameter_name"></a> [vault\_pki\_intermediate\_ca\_ssm\_parameter\_name](#output\_vault\_pki\_intermediate\_ca\_ssm\_parameter\_name) | SSM Parameter for the Vault PKI intermediate CA PEM. |
| <a name="output_vault_pki_signed_intermediate_ca_secret_arn"></a> [vault\_pki\_signed\_intermediate\_ca\_secret\_arn](#output\_vault\_pki\_signed\_intermediate\_ca\_secret\_arn) | Secrets Manager ARN for the Vault PKI signed intermediate CA PEM. |
| <a name="output_vault_snapshot_aws_s3_bucket_name"></a> [vault\_snapshot\_aws\_s3\_bucket\_name](#output\_vault\_snapshot\_aws\_s3\_bucket\_name) | Name of the S3 bucket for Vault Enterprise snapshots. |
| <a name="output_vault_url"></a> [vault\_url](#output\_vault\_url) | URL of the Vault Enterprise cluster. |
| <a name="output_vault_version"></a> [vault\_version](#output\_vault\_version) | Vault Enterprise version deployed. |
<!-- END_TF_DOCS -->
