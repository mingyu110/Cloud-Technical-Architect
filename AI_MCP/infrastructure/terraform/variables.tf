variable "aws_region" {
  description = "AWS区域"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "部署环境 (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "项目名称"
  type        = string
  default     = "ai-mcp-chatbot"
}

variable "tags" {
  description = "所有资源通用的标签"
  type        = map(string)
  default     = {
    Project     = "AI_MCP"
    CreatedBy   = "Terraform"
  }
} 