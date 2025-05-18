output "layer_arn" {
  description = "Lambda Layer ARN"
  value       = aws_lambda_layer_version.lambda_layer.arn
}

output "layer_name" {
  description = "Lambda Layer 名称"
  value       = aws_lambda_layer_version.lambda_layer.layer_name
}

output "layer_version" {
  description = "Lambda Layer 版本"
  value       = aws_lambda_layer_version.lambda_layer.version
} 