module "vpc" {
  count = var.vpc.existing == null ? 1 : 0

  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = var.vpc.name
  cidr = var.vpc.cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = var.vpc.private_subnets
  public_subnets  = var.vpc.public_subnets

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true
}

# VPC Endpoints

resource "aws_vpc_endpoint" "secretsmanager" {
  count = var.vpc.existing == null ? 1 : 0

  vpc_id              = module.vpc[0].vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc[0].private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = {
    Name = var.vpc_endpoints.secretsmanager_name
  }
}

resource "aws_vpc_endpoint" "kms" {
  count = var.vpc.existing == null ? 1 : 0

  vpc_id              = module.vpc[0].vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.kms"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc[0].private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = {
    Name = var.vpc_endpoints.kms_name
  }
}

resource "aws_vpc_endpoint" "ec2" {
  count = var.vpc.existing == null ? 1 : 0

  vpc_id              = module.vpc[0].vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.ec2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc[0].private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = {
    Name = var.vpc_endpoints.ec2_name
  }
}

resource "aws_vpc_endpoint" "s3" {
  count = var.vpc.existing == null ? 1 : 0

  vpc_id            = module.vpc[0].vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc[0].private_route_table_ids

  tags = {
    Name = var.vpc_endpoints.s3_name
  }
}

# Security Groups

resource "aws_security_group" "bastion" {
  name_prefix = var.security_groups.bastion_name_prefix
  description = "Vault Enterprise bastion host security group"
  vpc_id      = local.vpc.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each = toset(var.bastion.allowed_cidrs)

  security_group_id = aws_security_group.bastion.id
  description       = "SSH from allowed CIDR"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "bastion_all" {
  security_group_id = aws_security_group.bastion.id
  description       = "All outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "vault" {
  name_prefix = var.security_groups.vault_servers_name_prefix
  description = "Vault Enterprise servers security group"
  vpc_id      = local.vpc.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "vault_api" {
  security_group_id = aws_security_group.vault.id
  description       = "Vault Enterprise API from VPC"
  from_port         = 8200
  to_port           = 8200
  ip_protocol       = "tcp"
  cidr_ipv4         = local.vpc.cidr
}

resource "aws_vpc_security_group_ingress_rule" "vault_api_external" {
  for_each = toset(var.nlb.api_allowed_cidrs)

  security_group_id = aws_security_group.vault.id
  description       = "Vault Enterprise API from external CIDR"
  from_port         = 8200
  to_port           = 8200
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "vault_cluster" {
  security_group_id            = aws_security_group.vault.id
  description                  = "Vault Enterprise cluster traffic"
  from_port                    = 8201
  to_port                      = 8201
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.vault.id
}

resource "aws_vpc_security_group_ingress_rule" "vault_ssh" {
  security_group_id            = aws_security_group.vault.id
  description                  = "SSH from the Vault Enterprise bastion host"
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.bastion.id
}

resource "aws_vpc_security_group_egress_rule" "vault_all" {
  security_group_id = aws_security_group.vault.id
  description       = "All outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "vpc_endpoints" {
  count = var.vpc.existing == null ? 1 : 0

  name_prefix = var.security_groups.vpc_endpoints_name_prefix
  description = "Vault Enterprise VPC endpoints security group"
  vpc_id      = module.vpc[0].vpc_id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_https" {
  count = var.vpc.existing == null ? 1 : 0

  security_group_id = aws_security_group.vpc_endpoints[0].id
  description       = "HTTPS from VPC"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = local.vpc.cidr
}
