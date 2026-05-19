terraform {
  required_version = "~> 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.45.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.2.1"
    }
  }
}
