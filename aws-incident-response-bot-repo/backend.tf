terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.7.0"
    }
  }


  backend "s3" {
    bucket         = "incident-response-bot-tfs"
    region         = "us-east-1"
    key            = "env/prod/terraform.tfstate"
    dynamodb_table = "incident-response-tf-lock-state-files"
    encrypt        = true
  }

}

provider "aws" {
  region = var.region
}
