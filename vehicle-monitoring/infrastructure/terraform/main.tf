provider "aws" {
  region = "us-east-1"  # 使用弗吉尼亚北部区域
}

# Kinesis Data Stream
resource "aws_kinesis_stream" "vehicle_metrics" {
  name             = "vehicle-metrics-stream"
  shard_count      = 1
  retention_period = 24

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  tags = {
    Environment = "dev"
    Project     = "vehicle-monitoring"
  }
}

# Timestream Database
resource "aws_timestreamwrite_database" "vehicle_metrics" {
  database_name = "vehicle_metrics"
}

# Timestream Table
resource "aws_timestreamwrite_table" "vehicle_data" {
  database_name = aws_timestreamwrite_database.vehicle_metrics.database_name
  table_name    = "vehicle_data"

  retention_properties {
    magnetic_store_retention_period_in_days = 30
    memory_store_retention_period_in_hours  = 24
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "vehicle_monitoring_lambda_role"

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
}

# IAM Policy for Lambda
resource "aws_iam_policy" "lambda_policy" {
  name        = "vehicle_monitoring_lambda_policy"
  description = "Policy for vehicle monitoring Lambda functions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "kinesis:PutRecord",
          "kinesis:PutRecords",
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:DescribeStream",
          "kinesis:ListShards",
          "timestream:WriteRecords",
          "timestream:DescribeEndpoints",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Lambda function for data generation
resource "aws_lambda_function" "data_generator" {
  filename         = "../../lambda_data_generator/vehicle_data_generator_lambda.zip"
  function_name    = "vehicle-data-generator"
  role            = aws_iam_role.lambda_role.arn
  handler         = "vehicle_data_generator_lambda.lambda_handler"
  runtime         = "python3.9"
  timeout         = 300
  memory_size     = 256

  environment {
    variables = {
      KINESIS_STREAM_NAME = aws_kinesis_stream.vehicle_metrics.name
      NUM_VEHICLES        = "10"
    }
  }
}

# Lambda function for data processing
resource "aws_lambda_function" "data_processor" {
  filename         = "../../lambda_stream_processor/vehicle_processor_lambda.zip"
  function_name    = "vehicle-data-processor"
  role            = aws_iam_role.lambda_role.arn
  handler         = "vehicle_processor_lambda.lambda_handler"
  runtime         = "python3.9"
  timeout         = 300
  memory_size     = 256

  environment {
    variables = {
      TIMESTREAM_DATABASE = aws_timestreamwrite_database.vehicle_metrics.database_name
      TIMESTREAM_TABLE    = aws_timestreamwrite_table.vehicle_data.table_name
    }
  }
}

# CloudWatch Event Rule for data generation
resource "aws_cloudwatch_event_rule" "data_generation" {
  name                = "vehicle-data-generation"
  description         = "Trigger vehicle data generation every minute"
  schedule_expression = "rate(1 minute)"
}

# CloudWatch Event Target
resource "aws_cloudwatch_event_target" "data_generation_target" {
  rule      = aws_cloudwatch_event_rule.data_generation.name
  target_id = "TriggerDataGeneration"
  arn       = aws_lambda_function.data_generator.arn
}

# Lambda permission for CloudWatch Events
resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_generator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.data_generation.arn
}

# Lambda Event Source Mapping for Kinesis to Lambda processor
resource "aws_lambda_event_source_mapping" "kinesis_to_processor" {
  event_source_arn  = aws_kinesis_stream.vehicle_metrics.arn
  function_name     = aws_lambda_function.data_processor.arn
  starting_position = "LATEST"
  batch_size        = 100
  enabled           = true
} 