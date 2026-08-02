terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = var.tags
  }
}

provider "aws" {
  region = "us-east-1"
  alias  = "aws_cloudfront"

  default_tags {
    tags = var.tags
  }
}
