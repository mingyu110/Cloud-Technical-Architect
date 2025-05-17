output "function_arn" {
  description = "Lambda函数的ARN"
  value       = aws_lambda_function.lambda.arn
}

output "function_name" {
  description = "Lambda函数的名称"
  value       = aws_lambda_function.lambda.function_name
}

output "role_arn" {
  description = "Lambda函数执行角色的ARN"
  value       = aws_iam_role.lambda_role.arn
}

output "role_name" {
  description = "Lambda函数执行角色的名称"
  value       = aws_iam_role.lambda_role.name
} 