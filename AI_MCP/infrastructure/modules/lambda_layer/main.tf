/*
 * 注意：此模块已弃用！
 * 推荐直接在AWS控制台创建Lambda Layer，然后在Terraform配置中使用Layer ARN
 * 请参阅项目README.md中的"使用AWS控制台创建Lambda Layer"部分
 */

resource "null_resource" "install_layer_dependencies" {
  triggers = {
    requirements = fileexists("${var.layer_source_path}/requirements.txt") ? filemd5("${var.layer_source_path}/requirements.txt") : "none"
  }
  
  provisioner "local-exec" {
    command = <<EOT
      echo "===== 开始构建 Lambda Layer: ${var.layer_name} ====="
      
      # 创建目录结构
      mkdir -p ${var.layer_source_path}/layer
      mkdir -p ${var.layer_source_path}/layer/python
      
      # 检查是否存在requirements.txt
      if [ -f "${var.layer_source_path}/requirements.txt" ]; then
        echo "找到依赖文件: ${var.layer_source_path}/requirements.txt"
        echo "安装依赖到 Layer..."
        
        # 列出将要安装的依赖
        echo "将安装以下依赖:"
        cat ${var.layer_source_path}/requirements.txt
        
        # 安装依赖
        pip install -r ${var.layer_source_path}/requirements.txt -t ${var.layer_source_path}/layer/python/
        
        # 检查安装结果
        if [ $? -eq 0 ]; then
          echo "依赖安装成功!"
          
          # 列出安装的包
          echo "已安装的包列表:"
          ls -la ${var.layer_source_path}/layer/python/
          
          # 特别检查fastmcp是否安装成功
          if [ -d "${var.layer_source_path}/layer/python/fastmcp" ]; then
            echo "FastMCP 安装成功!"
          else
            echo "警告: 未找到 FastMCP 包，请检查安装是否成功"
          fi
        else
          echo "错误: 依赖安装失败!"
          exit 1
        fi
      else
        echo "警告: 未找到 requirements.txt 文件"
      fi
      
      echo "===== 完成 Lambda Layer: ${var.layer_name} 构建 ====="
    EOT
  }
}

# 将 Layer 依赖打包为 ZIP
data "archive_file" "layer_package" {
  type        = "zip"
  source_dir  = "${var.layer_source_path}/layer"
  output_path = "${path.module}/files/${var.layer_name}.zip"
  
  depends_on = [
    null_resource.install_layer_dependencies
  ]
}

# 创建 Lambda Layer
resource "aws_lambda_layer_version" "lambda_layer" {
  layer_name = var.layer_name
  description = var.description
  
  filename         = data.archive_file.layer_package.output_path
  source_code_hash = data.archive_file.layer_package.output_base64sha256
  
  compatible_runtimes = var.compatible_runtimes
  
  lifecycle {
    create_before_destroy = true
  }
} 