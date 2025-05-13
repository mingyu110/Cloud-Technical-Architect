/******************************************
  Remote backend configuration
 *****************************************/

terraform {
  backend "s3" {
    bucket  = "123456789-operations-terraform"
    key     = "terraform_state_operations"
    region  = "eu-west-3"
    profile = "operations"
  }
}