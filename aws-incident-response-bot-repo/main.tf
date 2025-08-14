# IAM Policy for Lambda
resource "aws_iam_policy" "lambda_incident_response_policy" {
  name        = "LambdaIncidentResponsePolicy"
  description = "Policy for Lambda to handle EC2 incident response"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:DescribeInstances",
          "ec2:ModifyInstanceAttribute",
          "ec2:CreateSnapshot",
          "ec2:DescribeVolumes",
          "ec2:DescribeNetworkInterfaces"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
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

# IAM Role for Lambda
resource "aws_iam_role" "lambda_incident_response_role" {
  name = "LambdaIncidentResponseRole"
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

# Attach IAM Policy to Role
resource "aws_iam_role_policy_attachment" "lambda_incident_response_policy_attachment" {
  role       = aws_iam_role.lambda_incident_response_role.name
  policy_arn = aws_iam_policy.lambda_incident_response_policy.arn
}

# Quarantine Security Group
resource "aws_security_group" "quarantine_sg" {
  name        = "Quarantine-SG"
  description = "Security group to isolate compromised EC2 instances"
  vpc_id      = var.vpc_id

  # No inbound or outbound rules to isolate the instance
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = []
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = []
  }

  tags = {
    Name = "Quarantine-SG"
  }
}

# Lambda Function
resource "aws_lambda_function" "lambda_incident_response_function" {
  function_name    = "IncidentResponseFunction"
  runtime          = "python3.9"
  handler          = "lambda_function.lambda_handler"
  role             = aws_iam_role.lambda_incident_response_role.arn
  filename         = data.archive_file.lambda_function_zip.output_path
  source_code_hash = data.archive_file.lambda_function_zip.output_base64sha256

  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.slack_webhook_url
      ISOLATION_SG_ID   = aws_security_group.quarantine_sg.id
    }
  }

  timeout = 60
}

# Zip the Lambda code
data "archive_file" "lambda_function_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

# Enable GuardDuty
resource "aws_guardduty_detector" "detector" {
  enable = true
}

# EventBridge Rule for GuardDuty Findings
resource "aws_cloudwatch_event_rule" "guardduty_rule" {
  name        = "GuardDuty-Incident-Trigger"
  description = "Triggers Lambda on high-severity GuardDuty findings"
  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", var.minimum_severity] }]
      resource = { resourceType = ["Instance"] }
    }
  })
}

# EventBridge Target (Lambda)
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.guardduty_rule.name
  target_id = "IncidentResponseLambda"
  arn       = aws_lambda_function.lambda_incident_response_function.arn
}

# Lambda Permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_incident_response_function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty_rule.arn
}