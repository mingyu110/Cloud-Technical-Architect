provider "aws" {
  region = var.aws_region
}

# Lambda函数 - 订单状态Mock API
module "order_mock_api" {
  source      = "../modules/lambda"
  name        = "order-mock-api"
  description = "订单状态模拟API"
  handler     = "order_mock_api.lambda_handler"
  runtime     = "python3.9"
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
  runtime     = "python3.9"
  source_path = "${path.module}/../../src/lambda/mcp_server"
  timeout     = 30
  memory_size = 256
  
  environment_variables = {
    ENVIRONMENT = var.environment
    MOCK_API_URL = module.order_mock_api_gateway.invoke_url
  }

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
  runtime     = "python3.9"
  source_path = "${path.module}/../../src/lambda/mcp_client"
  timeout     = 60
  memory_size = 512
  
  environment_variables = {
    ENVIRONMENT = var.environment
    MCP_SERVER_URL = module.mcp_server_api_gateway.invoke_url
  }

  tags = {
    Project     = "AI_MCP"
    Environment = var.environment
  }

  # 为Bedrock添加额外的IAM权限
  additional_policies = [
    "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
  ]
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