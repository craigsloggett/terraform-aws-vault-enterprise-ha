data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_vpc" "existing" {
  count = var.vpc.existing != null ? 1 : 0
  id    = var.vpc.existing.vpc_id
}
