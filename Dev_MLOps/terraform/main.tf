provider "aws" {
  region = var.aws_region
}

module "networking" {
  source = "./networking"
}

module "eks" {
  source = "./eks"
  vpc_id = module.networking.vpc_id
}

module "s3" {
  source = "./s3"
}

module "ecr" {
  source = "./ecr"
}

module "iam" {
  source = "./iam"
}

module "cicd" {
  source = "./cicd"
}
