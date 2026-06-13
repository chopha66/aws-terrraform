terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.17.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # 스크립트 사용안하는 케이스
  #assume_role {
  #  role_arn     = var.assume_role_arn
  #  session_name = var.atlantis_user
  #}
}