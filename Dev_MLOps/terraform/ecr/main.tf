resource "aws_ecr_repository" "data_ingestion" {
  name = "data-ingestion"
}

resource "aws_ecr_repository" "model_training" {
  name = "model-training"
}

resource "aws_ecr_repository" "model_serving" {
  name = "model-serving"
}
