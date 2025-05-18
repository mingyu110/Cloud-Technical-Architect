variable "layer_name" {
  description = "Lambda Layer 名称"
  type        = string
}

variable "description" {
  description = "Lambda Layer 描述"
  type        = string
  default     = ""
}

variable "layer_source_path" {
  description = "Layer 依赖的源路径，应包含 requirements.txt 文件"
  type        = string
}

variable "compatible_runtimes" {
  description = "兼容的 Lambda 运行时列表"
  type        = list(string)
  default     = ["python3.10"]
} 