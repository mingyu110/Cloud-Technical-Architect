resource "aws_codecommit_repository" "mlops_repo" {
  repository_name = "mlops-infra"
  description     = "Infrastructure as Code for MLOps"
}
