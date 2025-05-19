provider "aws" {
  region = var.aws_region
}

# 使用AWS控制台创建的Python依赖Layer
variable "lambda_layer_arn" {
  description = "ARN of the Lambda Layer created in AWS Console"
  type        = string
  default     = "" # 需要手动填入从AWS控制台创建的Layer ARN
}

# Lambda函数 - 订单状态Mock API
module "order_mock_api" {
  source      = "../modules/lambda"
  name        = "order-mock-api"
  description = "订单状态模拟API"
  handler     = "order_mock_api.lambda_handler"
  runtime     = "python3.10"
  source_path = "${path.module}/../../src/lambda/order_mock_api"
  
  environment_variables = {
    ENVIRONMENT = var.environment
  }

  tags = {
    Project     = "AI_MCP"
    Environment = var.environment
  }
}

# Lambda函数 - MCP服务器
module "mcp_server" {
  source      = "../modules/lambda"
  name        = "mcp-order-status-server"
  description = "MCP订单状态服务器"
  handler     = "mcp_server.lambda_handler"
  runtime     = "python3.10"
  source_path = "${path.module}/../../src/lambda/mcp_server"
  timeout     = 30
  memory_size = 256
  
  environment_variables = {
    ENVIRONMENT = var.environment
    MOCK_API_URL = "${module.order_mock_api_gateway.invoke_url}"
  }

  layers = [
    var.lambda_layer_arn
  ]

  tags = {
    Project     = "AI_MCP"
    Environment = var.environment
  }
}

# Lambda函数 - MCP客户端
module "mcp_client" {
  source      = "../modules/lambda"
  name        = "mcp-client"
  description = "MCP客户端，集成Bedrock"
  handler     = "mcp_client.lambda_handler"
  runtime     = "python3.10"
  source_path = "${path.module}/../../src/lambda/mcp_client"
  timeout     = 120
  memory_size = 1024
  
  environment_variables = {
    ENVIRONMENT = var.environment
    MCP_SERVER_URL = "${module.mcp_server_api_gateway.invoke_url}"
    MODEL_ID = "anthropic.claude-3-sonnet-20240229-v1:0"
  }

  layers = [
    var.lambda_layer_arn
  ]

  tags = {
    Project     = "AI_MCP"
    Environment = var.environment
  }

  additional_policies = [
    "arn:aws:iam::aws:policy/AmazonBedrockReadOnly",
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
  ]
}

# 为 MCP 客户端创建自定义 Bedrock 调用权限
resource "aws_iam_policy" "bedrock_invoke_policy" {
  name        = "bedrock-model-invoke-policy"
  description = "允许调用 Bedrock 模型"
  
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ],
        Resource = [
          "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0"
        ]
      }
    ]
  })
}

# 附加 Bedrock 调用权限
resource "aws_iam_role_policy_attachment" "bedrock_invoke_attachment" {
  role       = module.mcp_client.role_name
  policy_arn = aws_iam_policy.bedrock_invoke_policy.arn
}

# API Gateway - Mock API
module "order_mock_api_gateway" {
  source        = "../modules/api_gateway"
  name          = "order-mock-api"
  description   = "API Gateway for Order Mock API"
  lambda_function_name = module.order_mock_api.function_name
  lambda_function_arn  = module.order_mock_api.function_arn
  stage_name    = var.environment
  
  tags = {
    Project     = "AI_MCP"
    Environment = var.environment
  }
}

# API Gateway - MCP服务器
module "mcp_server_api_gateway" {
  source        = "../modules/api_gateway"
  name          = "mcp-server"
  description   = "API Gateway for MCP Server"
  lambda_function_name = module.mcp_server.function_name
  lambda_function_arn  = module.mcp_server.function_arn
  stage_name    = var.environment
  
  tags = {
    Project     = "AI_MCP"
    Environment = var.environment
  }
}

# API Gateway - 聊天机器人端点
module "chatbot_api_gateway" {
  source        = "../modules/api_gateway"
  name          = "chatbot-api"
  description   = "API Gateway for Chatbot Client"
  lambda_function_name = module.mcp_client.function_name
  lambda_function_arn  = module.mcp_client.function_arn
  stage_name    = var.environment
  
  tags = {
    Project     = "AI_MCP"
    Environment = var.environment
  }
} 