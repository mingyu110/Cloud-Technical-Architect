output "codecommit_repo" {
  value = aws_codecommit_repository.mlops_repo.clone_url_http
}
