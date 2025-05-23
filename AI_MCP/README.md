# AI_MCP 项目

## 项目概述

基于AWS Bedrock、AWS Lambda、AWS API Gateway和MCP打造的智能客户支持聊天机器人系统。该项目实现了最新的Model Context Protocol (MCP) v2025.03.26规范，采用Streamable HTTP Transport技术，提供完整的订单查询和AI对话功能。

## 🚀 快速开始

**全新自动化脚本，5分钟完成部署！**

```bash
# 1. 克隆项目并进入目录
git clone <repository-url>
cd AI_MCP

# 2. 一键构建和部署Layer（解决所有兼容性问题）
./scripts/prepare_py311_layer.sh

# 3. 部署基础设施
cd infrastructure/terraform
terraform init && terraform apply

# 4. 测试所有API
cd ../..
./scripts/test_all_apis.sh

# 5. 如有问题，运行调试工具
./scripts/debug_lambda.sh  # 选择选项9进行完整诊断
```

## 技术架构

### MCP v2025.03.26 规范

Anthropic于2025年3月发布了Model Context Protocol (MCP) v2025.03.26，引入了**Streamable HTTP Transport**，替换了之前的HTTP+SSE传输协议。本项目实现了完整的MCP规范，支持无状态serverless部署。

### 核心特性

| 特性 | 说明 | 优势 |
|-----|-----|-----|
| **Streamable HTTP Transport** | 基于HTTP的无状态传输 | 适合Lambda部署，成本效益高 |
| **JSON-RPC编码** | 标准JSON-RPC 2.0协议 | 兼容性好，调试友好 |
| **多模型支持** | Amazon Titan、Claude v2/v3 | 灵活的AI模型选择 |
| **平台兼容性** | Linux x86_64优化构建 | 解决macOS到Lambda的兼容性问题 |
| **自动化运维** | 完整的脚本工具链 | 一键部署、测试、调试 |

### 系统架构图

```
┌─────────────┐    ┌──────────────┐    ┌─────────────┐    ┌──────────────┐
│   用户查询   │───→│ Chatbot API  │───→│ MCP Server  │───→│ Mock API     │
│            │    │ (AI智能回复)  │    │ (工具调用)   │    │ (订单数据)    │
└─────────────┘    └──────────────┘    └─────────────┘    └──────────────┘
                          │                    │                   │
                          ▼                    ▼                   ▼
                   ┌──────────────┐    ┌─────────────┐    ┌──────────────┐
                   │ AWS Bedrock  │    │ FastAPI +   │    │ 独立Lambda   │
                   │ (Titan/Claude)│    │ Mangum     │    │ 函数         │
                   └──────────────┘    └─────────────┘    └──────────────┘
                          │                    │                   │
                          ▼                    ▼                   ▼
                   ┌──────────────────────────────────────────────────────┐
                   │           AWS Lambda + API Gateway                    │
                   │         共享Layer: mcp-dependencies                   │
                   └──────────────────────────────────────────────────────┘
```

## 项目结构

```
AI_MCP/
├── 📁 infrastructure/          # 基础设施即代码
│   ├── modules/               # Terraform模块
│   │   ├── api_gateway/       # API Gateway配置
│   │   └── lambda/            # Lambda函数配置
│   └── terraform/             # 主Terraform配置
├── 📁 scripts/                # 🆕 自动化运维脚本
│   ├── prepare_py311_layer.sh # Layer构建和部署
│   ├── test_all_apis.sh       # 端到端API测试
│   ├── debug_lambda.sh        # 交互式调试工具
│   └── README.md              # 脚本使用说明
├── 📁 src/                    # 源代码
│   ├── lambda/
│   │   ├── mcp_client/        # AI聊天机器人（Bedrock集成）
│   │   ├── mcp_server/        # MCP工具服务器（FastAPI）
│   │   └── order_mock_api/    # 订单数据模拟API
│   └── tests/                 # 测试代码
├── 📄 AI_MCP_Debugging_Guide.md # 🆕 完整调试实战指南
├── 📄 requirements.txt         # Python依赖
└── 📄 README.md               # 项目说明（本文件）
```

## 🔧 组件详解

### 1. **Chatbot API** (mcp_client)
- **功能**：智能客户服务聊天机器人
- **AI模型**：支持Amazon Titan、Claude v2/v3
- **特性**：订单信息提取、自然语言理解、多模型API适配
- **端点**：`/chat` (POST)，`/health` (GET)

### 2. **MCP Server** (mcp_server)
- **功能**：MCP工具服务器，提供订单查询工具
- **技术**：FastAPI + Mangum + JSON-RPC 2.0
- **工具**：`get_order_status` - 订单状态查询
- **端点**：`/mcp` (POST)，`/health` (GET)

### 3. **Mock API** (order_mock_api)
- **功能**：订单数据模拟服务
- **特性**：独立部署，模拟真实订单系统
- **数据**：订单ID、状态、物流信息
- **端点**：`/orders/{order_id}` (GET)，`/health` (GET)

### 4. **共享依赖层** (mcp-dependencies)
- **优化**：Linux x86_64平台特定构建
- **依赖**：mcp>=1.9.1, fastapi>=0.109.0, boto3>=1.37.3
- **兼容**：Python 3.11，解决pydantic_core兼容性问题

## 🚀 部署指南

### 环境要求

- **AWS账户**：已配置CLI和适当权限
- **工具**：Terraform 1.0+, Python 3.8+, curl, aws-cli
- **区域**：推荐us-east-1（Bedrock可用区域）
- **权限**：Lambda、API Gateway、Bedrock、CloudWatch Logs

### 自动化部署（推荐）

#### 方式一：完全自动化
```bash
# 克隆项目
git clone <repository-url> && cd AI_MCP

# 一键部署（包含Layer构建、AWS上传、Lambda更新）
./scripts/prepare_py311_layer.sh

# 部署基础设施
cd infrastructure/terraform
terraform init
terraform apply -auto-approve

# 验证部署
cd ../..
./scripts/test_all_apis.sh
```

#### 方式二：分步部署
```bash
# 1. 构建Layer（解决平台兼容性）
./scripts/prepare_py311_layer.sh

# 2. 配置Terraform变量（如需自定义）
cd infrastructure/terraform
cp terraform.tfvars.example terraform.tfvars
# 编辑terraform.tfvars设置区域等参数

# 3. 部署基础设施
terraform init
terraform plan    # 检查部署计划
terraform apply   # 确认后部署

# 4. 端到端测试
cd ../..
./scripts/test_all_apis.sh
```

### 手动部署（备用方案）

如果自动化脚本无法使用：

```bash
# 1. 手动构建Layer
mkdir -p layer_build/python
python3 -m pip install -r requirements.txt \
  -t layer_build/python/ \
  --platform manylinux2014_x86_64 \
  --python-version 3.11 \
  --only-binary=:all:

cd layer_build && zip -r ../py311_layer.zip python/
cd ..

# 2. 上传Layer
aws lambda publish-layer-version \
  --layer-name mcp-dependencies \
  --zip-file fileb://py311_layer.zip \
  --compatible-runtimes python3.11

# 3. 更新terraform.tfvars
# 将获得的Layer ARN添加到配置中

# 4. 部署
cd infrastructure/terraform
terraform apply
```

## 🧪 测试和验证

### 自动化测试

```bash
# 运行完整测试套件（8个测试用例）
./scripts/test_all_apis.sh

# 输出示例：
# 🧪 AI_MCP项目 - 全面API测试
# === 测试1: Mock API - 订单状态查询 ===
# ✅ HTTP状态码正确 (200)
# ✅ 响应为有效JSON格式
# === 测试结果摘要 ===
# 总测试数: 8
# 通过测试: 8
# 成功率: 100%
# 🎉 所有测试通过！系统运行正常
```

### 手动测试API

获取部署后的API端点：
```bash
cd infrastructure/terraform
terraform output
```

#### 测试Mock API
```bash
MOCK_API_URL="<your-mock-api-url>"
curl "$MOCK_API_URL/orders/12345"
# 预期输出: {"order_id": "12345", "status": "已发货，预计3天内送达"}
```

#### 测试MCP Server
```bash
MCP_SERVER_URL="<your-mcp-server-url>"
curl -X POST "$MCP_SERVER_URL/mcp" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": "test-1",
    "method": "call_tool",
    "params": {
      "name": "get_order_status",
      "params": {"order_id": "12345"}
    }
  }'
# 预期输出: {"jsonrpc":"2.0","id":"test-1","result":"订单 12345 的状态是: 已发货，预计3天内送达"}
```

#### 测试Chatbot API
```bash
CHATBOT_API_URL="<your-chatbot-api-url>"
curl -X POST "$CHATBOT_API_URL/chat" \
  -H "Content-Type: application/json" \
  -d '{"query": "查询订单12345的状态"}'
# 预期输出: AI生成的智能中文回复
```

## 🔧 故障排除

### 一键诊断工具

```bash
# 启动交互式调试工具
./scripts/debug_lambda.sh

# 选择选项9进行完整诊断，包括：
# ✅ Layer兼容性检查
# ✅ 导入错误检测  
# ✅ 错误日志分析
# ✅ Bedrock权限验证
# ✅ Terraform状态同步
```

### 常见问题速查

#### 🚨 Layer兼容性问题
**错误**: `No module named 'pydantic_core'` 或 `_pydantic_core`
```bash
# 解决方案：重新构建Layer（使用正确的平台）
./scripts/prepare_py311_layer.sh

# 或使用调试工具自动修复
./scripts/debug_lambda.sh  # 选择选项6
```

#### 🚨 Bedrock权限问题
**错误**: `AccessDeniedException: You don't have access to the model`
```bash
# 1. 检查模型权限
./scripts/debug_lambda.sh  # 选择选项7

# 2. 手动申请权限
# 访问AWS Bedrock控制台 -> 模型访问权限 -> 申请Amazon Titan
```

#### 🚨 Shell配置冲突
**错误**: `head: |: No such file or directory`
```bash
# 解决方案：所有脚本已自动设置
export AWS_PAGER=""
```

#### 🚨 Unicode编码问题
**现象**: 返回 `\u5f88\u62b1\u6b49` 而不是中文
```bash
# 已在代码中修复：json.dumps(body, ensure_ascii=False, indent=2)
# 如仍有问题，检查 Content-Type: application/json; charset=utf-8
```

### 日志查看

```bash
# 实时查看日志
aws logs tail /aws/lambda/mcp-client --follow

# 查看错误日志
./scripts/debug_lambda.sh  # 选择选项3

# 手动查看最近日志
aws logs get-log-events \
  --log-group-name "/aws/lambda/mcp-client" \
  --log-stream-name $(aws logs describe-log-streams \
    --log-group-name "/aws/lambda/mcp-client" \
    --order-by LastEventTime --descending --limit 1 \
    --query 'logStreams[0].logStreamName' --output text)
```

## 🛠️ 开发和维护

### 日常开发工作流

```bash
# 1. 修改依赖或代码后，重新构建Layer
./scripts/prepare_py311_layer.sh

# 2. 更新基础设施（如有配置变更）
cd infrastructure/terraform && terraform apply

# 3. 验证所有功能
./scripts/test_all_apis.sh

# 4. 如有问题，使用调试工具
./scripts/debug_lambda.sh
```

### Layer版本管理

```bash
# 查看当前Layer版本
aws lambda list-layer-versions --layer-name mcp-dependencies

# 检查函数使用的Layer版本
./scripts/debug_lambda.sh  # 选择选项4

# 更新到最新Layer版本
./scripts/debug_lambda.sh  # 选择选项6
```

### 性能优化建议

- **超时设置**：MCP相关函数建议30秒以上
- **内存配置**：客户端函数建议1024MB
- **并发控制**：根据需要配置预留并发
- **监控告警**：设置CloudWatch告警监控错误率和延迟

## 📚 文档和资源

### 项目文档
- **📄 [调试指南](AI_MCP_Debugging_Guide.md)** - 详细的调试实战经验
- **📄 [脚本说明](scripts/README.md)** - 自动化脚本使用指南

### 技术参考
- [MCP Specification v2025.03.26](https://modelcontextprotocol.io/specification/2025-03-26/)
- [AWS Lambda with MCP](https://github.com/awslabs/run-model-context-protocol-servers-with-aws-lambda)
- [AWS Bedrock Documentation](https://docs.aws.amazon.com/bedrock/)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)

### API端点引用

部署完成后，您将获得以下端点：

| API | 端点 | 功能 |
|-----|------|------|
| **Chatbot API** | `https://{api-id}.execute-api.us-east-1.amazonaws.com/dev/chat` | AI智能对话 |
| **MCP Server** | `https://{api-id}.execute-api.us-east-1.amazonaws.com/dev/mcp` | MCP工具调用 |
| **Mock API** | `https://{api-id}.execute-api.us-east-1.amazonaws.com/dev/orders/{id}` | 订单查询 |

## 🤝 贡献和支持

### 贡献指南
1. Fork项目并创建特性分支
2. 遵循现有的代码风格和错误处理模式
3. 添加相应的测试用例
4. 更新相关文档
5. 提交Pull Request

### 获取支持
- **问题反馈**：使用GitHub Issues
- **调试帮助**：参考调试指南和使用调试工具
- **最佳实践**：查看scripts/README.md

---

*🚀 基于AWS和MCP v2025.03.26的智能客服系统 - 完整的部署、测试、调试工具链*

