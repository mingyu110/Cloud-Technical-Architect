variable "name" {
  description = "API Gateway名称"
  type        = string
}

variable "description" {
  description = "API Gateway描述"
  type        = string
  default     = ""
}

variable "lambda_function_name" {
  description = "要集成的Lambda函数名称"
  type        = string
}

variable "lambda_function_arn" {
  description = "要集成的Lambda函数ARN"
  type        = string
}

variable "stage_name" {
  description = "API Gateway部署阶段名称"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS区域"
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "API Gateway资源的标签"
  type        = map(string)
  default     = {}
} 