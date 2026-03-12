# AWS S3

#terraform {
#  backend "s3" {
#    bucket         = "s3-bucket-name"
#    dynamodb_table = "dynamo-db-table-name"
#    key            = "my-module-infrastructure.tfstate"
#    encrypt        = true
#    kms_key_id     = "alias/aws/s3"
#    region         = "us-east-1"
#  }
#}

# HCP Terraform

#terraform {
#  cloud {
#    organization = "my-org"
#    hostname     = "app.terraform.io" # Optional; defaults to app.terraform.io
#
#    workspaces {
#      project = "networking-team"
#      name    = "networking-dev"
#    }
#  }
#}
