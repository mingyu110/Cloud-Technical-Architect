variable "name" {
  description = "Lambda函数名称"
  type        = string
}

variable "description" {
  description = "Lambda函数描述"
  type        = string
  default     = ""
}

variable "handler" {
  description = "Lambda处理函数"
  type        = string
}

variable "runtime" {
  description = "Lambda运行时环境"
  type        = string
  default     = "python3.9"
}

variable "source_path" {
  description = "Lambda源代码的路径"
  type        = string
}

variable "timeout" {
  description = "Lambda超时时间（秒）"
  type        = number
  default     = 10
}

variable "memory_size" {
  description = "Lambda内存大小（MB）"
  type        = number
  default     = 128
}

variable "environment_variables" {
  description = "Lambda环境变量"
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "CloudWatch日志保留天数"
  type        = number
  default     = 14
}

variable "tags" {
  description = "Lambda资源的标签"
  type        = map(string)
  default     = {}
}

variable "additional_policies" {
  description = "要附加到Lambda角色的额外IAM策略ARN列表"
  type        = list(string)
  default     = []
} 