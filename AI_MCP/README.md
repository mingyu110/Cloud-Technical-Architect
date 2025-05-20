# AI_MCP 项目

- 基于AWS BedRock、AWS Lambda、AWS API Gateway和MCP打造的客户支持聊天机器人系统。
- 注意：目前该项目还有问题没有解决，所以暂时不可用，正在修复中！！

## 项目结构

```
AI_MCP
├── docs                      # 项目文档
├── infrastructure            # 基础设施代码
│   ├── modules               # Terraform模块
│   │   ├── api_gateway       # API Gateway模块
│   │   ├── lambda            # Lambda模块
│   │   └── lambda_layer      # Lambda Layer模块（已弃用，改为使用AWS控制台创建Layer）
│   └── terraform             # Terraform主配置
├── scripts                   # 辅助脚本
│   └── prepare_layer_dependencies.sh # 准备Layer依赖辅助脚本
├── src                       # 源代码
│   ├── lambda                # Lambda函数代码
│   │   ├── mcp_client        # MCP客户端，集成Bedrock
│   │   ├── mcp_server        # MCP服务器
│   │   └── order_mock_api    # 订单状态模拟API
│   └── tests                 # 测试代码
└── requirements.txt          # 项目依赖
```

## 组件说明

### 1. 订单状态模拟API (order_mock_api)

- 功能：模拟订单数据库API，返回订单状态信息
- 技术：AWS Lambda + API Gateway
- 接口：接收订单ID，返回订单状态
- 健康检查：支持GET `/health` 端点检查服务健康状态

### 2. MCP服务器 (mcp_server)

- 功能：实现MCP (Model Control Protocol) 服务器，提供订单查询工具
- 技术：AWS Lambda + API Gateway
- 工具：get_order_status - 获取订单状态
- 健康检查：支持GET `/health` 端点

### 3. MCP客户端 (mcp_client)

- 功能：集成AWS Bedrock，处理用户查询，调用MCP服务器
- 技术：AWS Lambda + API Gateway + AWS Bedrock
- 处理：解析用户查询，提取订单信息，调用LLM生成自然语言响应
- 模型：默认使用Claude v2 (anthropic.claude-v2)，可通过环境变量配置
- 健康检查：支持GET `/health` 查询和错误统计

### 4. 共享依赖层 (Lambda Layer)

- 功能：共享Python依赖，提高部署效率，减小Lambda包大小
- 包含：requests>=2.31.0, boto3>=1.28.0, pytest>=7.4.0, pydantic>=2.4.2,<2.5.0等库
- 兼容：Python 3.10 运行时
- 部署：通过AWS控制台创建，提高构建速度和稳定性

## 部署说明

### 前提条件

- AWS账户和CLI配置
- Terraform 1.0+
- Python 3.10+

### 使用脚本创建Lambda Layer（推荐）

为了简化Layer依赖准备过程并确保兼容性，项目提供了专用脚本来准备Lambda Layer：

1. **执行依赖准备脚本**：
   ```bash
   # 确保脚本有执行权限
   chmod +x scripts/prepare_layer_dependencies.sh
   
   # 运行脚本准备Layer依赖
   ./scripts/prepare_layer_dependencies.sh
   ```
   
   脚本会自动：
   - 安装所有必要的依赖（包括boto3, requests, pydantic等）
   - 打包依赖为layer.zip文件
   - 在当前目录生成可直接上传的ZIP文件

2. **在AWS控制台创建Layer**：
   - 登录AWS管理控制台，进入Lambda服务
   - 在左侧导航栏选择"Layers"
   - 点击"Create layer"按钮
   - 填写Layer基本信息：
     - 名称：`mcp-dependencies`
     - 描述：`MCP 系统依赖库 Layer`
   - 在"Upload"部分选择"Upload a zip file"，上传脚本生成的layer.zip文件
   - 选择兼容的运行时：Python 3.10
   - 点击"Create"创建Layer

3. **获取Layer ARN**：
   - Layer创建完成后，在Layer详情页面复制ARN
   - ARN格式类似：`arn:aws:lambda:us-east-1:123456789012:layer:mcp-dependencies:1`

> **注意**：使用脚本方式创建Layer比手动安装依赖更可靠。

### 使用Terraform部署应用

1. 克隆仓库：
   ```
   git clone https://github.com/yourusername/AI_MCP.git
   cd AI_MCP
   ```

2. 创建Lambda Layer并获取ARN：
   ```bash
   # 按照上述"使用脚本创建Lambda Layer"部分的步骤操作
   # 确保已获取Layer ARN
   ```

3. 更新Terraform变量，提供Lambda Layer ARN：
   ```bash
   # 创建或编辑terraform.tfvars文件
   echo 'lambda_layer_arn = "您的Layer ARN"' > infrastructure/terraform/terraform.tfvars
   
   # 您也可以手动编辑文件，确保包含：
   # lambda_layer_arn = "arn:aws:lambda:区域:账号:layer:mcp-dependencies:版本"
   ```

4. 执行Terraform部署：
   ```bash
   cd infrastructure/terraform
   terraform init
   terraform plan  # 检查计划
   terraform apply # 应用部署
   ```

5. 部署完成后，记录输出的API Gateway URL，用于测试服务：
   ```bash
   # 查看部署输出
   terraform output
   ```

## 功能验证

### 1. 验证订单模拟API

```bash
# 健康检查
curl -X GET "$(terraform output -raw mock_api_url)/health"

# 查询订单状态
curl -X POST "$(terraform output -raw mock_api_url)" \
  -H "Content-Type: application/json" \
  -d '{"order_id": "12345"}'
```

预期输出：
```json
{
  "order_id": "12345",
  "status": "已发货",
  "environment": "dev",
  "request_id": "4a7d8f01-..."
}
```

### 2. 验证MCP服务器

```bash
# 健康检查
curl -X GET "$(terraform output -raw mcp_server_url)/health"

# 列出可用工具
curl -X POST "$(terraform output -raw mcp_server_url)" \
  -H "Content-Type: application/json" \
  -d '{"tool_name": "__list_tools__"}'

# 查询订单状态
curl -X POST "$(terraform output -raw mcp_server_url)" \
  -H "Content-Type: application/json" \
  -d '{"tool_name": "get_order_status", "params": {"order_id": "12345"}}'
```

### 3. 验证聊天机器人集成

```bash
# 健康检查
curl -X GET "$(terraform output -raw chatbot_api_url)/health"

# 发送用户查询
curl -X POST "$(terraform output -raw chatbot_api_url)" \
  -H "Content-Type: application/json" \
  -d '{"query": "我的订单12345什么时候到？"}'
```

预期输出：
```json
{
  "response": "您的订单12345目前状态是已发货，预计会在3-5个工作日内送达。如有其他问题，请随时咨询。",
  "query": "我的订单12345什么时候到？",
  "extracted_order_id": "12345"
}
```

## 故障排除

如果遇到部署或功能问题，请检查：

1. **Lambda依赖问题**：
   - 检查 CloudWatch 日志是否显示缺少依赖项
   - 确认 Lambda Layer 已正确配置和部署
   - 使用部署脚本重新部署以解决依赖问题

2. **API Gateway配置**：
   - 检查 API Gateway 阶段是否正确部署
   - 确认 Lambda 权限是否允许 API Gateway 调用

3. **Bedrock访问权限**：
   - 确认 MCP 客户端 Lambda 有合适的 Bedrock 调用权限
   - 检查是否使用了正确的模型 ID

### API Gateway 错误: "Internal server error"

如果通过 API Gateway 访问 Lambda 函数时收到 "Internal server error" 错误，可以尝试以下解决方法：

1. **直接调用 Lambda 函数进行测试**：
   ```bash
   # 创建测试事件文件
   echo '{"httpMethod":"GET","path":"/health"}' > test_event.json
   
   # 使用 Lambda 函数的 CLI 调用
   aws lambda invoke --function-name mcp-order-status-server \
     --cli-binary-format raw-in-base64-out \
     --payload file://test_event.json response.json
   
   # 查看响应
   cat response.json
   ```

2. **检查日志**：
   ```bash
   # 获取最新的日志
   aws logs get-log-events \
     --log-group-name /aws/lambda/mcp-order-status-server \
     --log-stream-name $(aws logs describe-log-streams \
       --log-group-name /aws/lambda/mcp-order-status-server \
       --order-by LastEventTime --descending --limit 1 \
       --query 'logStreams[0].logStreamName' --output text)
   ```

### Lambda Layer依赖问题

如果遇到依赖问题，特别是与pydantic相关的错误，请尝试以下解决方法：

1. **使用项目提供的脚本重新创建Layer**：
   ```bash
   # 运行依赖准备脚本
   ./scripts/prepare_layer_dependencies.sh
   
   # 在AWS控制台上传新的layer.zip并创建新版本
   ```

2. **确认Layer包含所有必要依赖**：
   脚本自动安装的核心依赖包括：
   ```
   boto3>=1.28.0
   requests>=2.31.0
   pytest>=7.4.0
   pydantic>=2.4.2,<2.5.0
   ```

3. **检查CloudWatch日志**：
   查看Lambda执行日志，确认具体的依赖错误信息
   ```bash
   # 使用AWS CLI查看最新日志
   aws logs get-log-events \
     --log-group-name /aws/lambda/mcp-client \
     --log-stream-name $(aws logs describe-log-streams \
       --log-group-name /aws/lambda/mcp-client \
       --order-by LastEventTime --descending --limit 1 \
       --query 'logStreams[0].logStreamName' --output text)
   ```

4. **更新Layer ARN**：
   - 在AWS控制台创建新版本的Layer后
   - 修改terraform.tfvars文件中的lambda_layer_arn值
   - 重新应用Terraform配置
   ```bash
   cd infrastructure/terraform
   terraform apply
   ```

## 开发指南

- 修改订单模拟数据：编辑 `src/lambda/order_mock_api/order_mock_api.py`
- 添加新的MCP工具：编辑 `src/lambda/mcp_server/mcp_server.py`
- 调整LLM提示模板：编辑 `src/lambda/mcp_client/mcp_client.py`
- 更改 Bedrock 模型：通过环境变量 `MODEL_ID` 配置
