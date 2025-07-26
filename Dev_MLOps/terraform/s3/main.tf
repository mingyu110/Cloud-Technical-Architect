resource "aws_s3_bucket" "mlops_data" {
  bucket = "mlops-data-${random_id.id.hex}"
  force_destroy = true

  tags = {
    Name = "MLOps Data Bucket"
  }
}

resource "random_id" "id" {
  byte_length = 4
}
