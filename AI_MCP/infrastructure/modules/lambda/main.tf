resource "aws_iam_role" "lambda_role" {
  name = "${var.name}-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  
  tags = var.tags
}

# 基本的Lambda执行权限
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# 添加额外的IAM策略（如果有）
resource "aws_iam_role_policy_attachment" "additional_policies" {
  count      = length(var.additional_policies)
  role       = aws_iam_role.lambda_role.name
  policy_arn = var.additional_policies[count.index]
}

# 将Lambda代码打包为ZIP
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = var.source_path
  output_path = "${path.module}/files/${var.name}.zip"
}

# Lambda函数
resource "aws_lambda_function" "lambda" {
  function_name    = var.name
  description      = var.description
  role             = aws_iam_role.lambda_role.arn
  handler          = var.handler
  runtime          = var.runtime
  timeout          = var.timeout
  memory_size      = var.memory_size
  
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  environment {
    variables = var.environment_variables
  }
  
  layers = var.layers
  
  tags = var.tags
}

# CloudWatch日志组
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.lambda.function_name}"
  retention_in_days = var.log_retention_days
  
  tags = var.tags
} 