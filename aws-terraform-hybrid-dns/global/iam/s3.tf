resource "aws_s3_bucket" "mingyu110-tf-statefiles-master" {
  bucket = "mingyu110-tf-statefiles-master"
}

resource "aws_s3_bucket_acl" "aws-s3-bucket-acl" {
  bucket = aws_s3_bucket.mingyu110-tf-statefiles-master.id
  acl    = "private"
}

resource "aws_s3_bucket_versioning" "aws-s3-bucket-versioning" {
  bucket = aws_s3_bucket.mingyu110-tf-statefiles-master.id
  versioning_configuration {
    status = "Enabled"
  }
}