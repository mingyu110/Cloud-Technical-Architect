resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "mlops-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true
  tags = { Name = "public-subnet" }
}
