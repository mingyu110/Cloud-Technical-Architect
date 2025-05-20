# API Gateway REST API
resource "aws_api_gateway_rest_api" "api" {
  name        = var.name
  description = var.description
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  
  tags = var.tags
  
  # 添加lifecycle块以处理已存在资源
  lifecycle {
    # 避免删除已存在的API
    prevent_destroy = true
    # 忽略某些难以更新的属性
    ignore_changes = [
      body,
      policy
    ]
  }
}

# API Gateway资源（路径）
resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "{proxy+}"
}

# ANY方法
resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

# 与Lambda集成 - 代理集成
resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy.http_method
  
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${var.lambda_function_arn}/invocations"
  
  # 确保超时设置合理
  timeout_milliseconds = 29000
  
  # 显式定义集成参数
  passthrough_behavior = "WHEN_NO_MATCH"
}

# 根路径方法
resource "aws_api_gateway_method" "proxy_root" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_rest_api.api.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}

# 根路径Lambda集成 - 代理集成
resource "aws_api_gateway_integration" "lambda_root" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_rest_api.api.root_resource_id
  http_method = aws_api_gateway_method.proxy_root.http_method
  
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${var.lambda_function_arn}/invocations"
  
  # 确保超时设置合理
  timeout_milliseconds = 29000
  
  # 显式定义集成参数
  passthrough_behavior = "WHEN_NO_MATCH"
}

# 添加OPTIONS方法支持CORS - 根路径
resource "aws_api_gateway_method" "options_root" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_rest_api.api.root_resource_id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# 添加OPTIONS方法集成 - 根路径
resource "aws_api_gateway_integration" "options_root" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_rest_api.api.root_resource_id
  http_method = aws_api_gateway_method.options_root.http_method
  
  type = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# 添加OPTIONS方法响应 - 根路径
resource "aws_api_gateway_method_response" "options_root" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_rest_api.api.root_resource_id
  http_method = aws_api_gateway_method.options_root.http_method
  status_code = "200"
  
  response_models = {
    "application/json" = "Empty"
  }
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# 添加OPTIONS方法集成响应 - 根路径
resource "aws_api_gateway_integration_response" "options_root" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_rest_api.api.root_resource_id
  http_method = aws_api_gateway_method.options_root.http_method
  status_code = aws_api_gateway_method_response.options_root.status_code
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS,PUT,DELETE'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# 部署API
resource "aws_api_gateway_deployment" "api" {
  depends_on = [
    aws_api_gateway_integration.lambda,
    aws_api_gateway_integration.lambda_root,
    aws_api_gateway_integration_response.options_root
  ]
  
  rest_api_id = aws_api_gateway_rest_api.api.id
  
  # 每次配置更改时强制重新部署
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.proxy.id,
      aws_api_gateway_method.proxy.id,
      aws_api_gateway_integration.lambda.id,
      aws_api_gateway_method.proxy_root.id,
      aws_api_gateway_integration.lambda_root.id,
      aws_api_gateway_method.options_root.id,
      aws_api_gateway_integration.options_root.id
    ]))
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# 创建API阶段
resource "aws_api_gateway_stage" "api_stage" {
  deployment_id = aws_api_gateway_deployment.api.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = var.stage_name
  
  tags = var.tags
}

# 启用API Gateway日志
resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.api_stage.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled = true
    logging_level   = "INFO"
  }
}

# 允许API Gateway调用Lambda - 更明确的权限定义
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  
  # 更明确地指定调用来源
  source_arn = "${aws_api_gateway_rest_api.api.execution_arn}/${var.stage_name}/*"
} 