output "api_id" {
  description = "API Gateway ID"
  value       = aws_api_gateway_rest_api.api.id
}

output "invoke_url" {
  description = "API Gateway调用URL"
  value       = "${aws_api_gateway_stage.api_stage.invoke_url}"
}

output "execution_arn" {
  description = "API Gateway执行ARN"
  value       = aws_api_gateway_rest_api.api.execution_arn
} 