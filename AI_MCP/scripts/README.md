# AI_MCP 项目脚本说明

本目录包含基于《AI_MCP_Debugging_Guide.md》调试经验优化的实用脚本，用于自动化部署、测试和调试AI_MCP项目。

## 📋 脚本概览

| 脚本名称 | 功能描述 | 使用频率 |
|---------|---------|----------|
| `prepare_py311_layer.sh` | Lambda Layer构建和部署 | 🔄 需要时 |
| `test_all_apis.sh` | 端到端API功能测试 | ✅ 经常使用 |
| `debug_lambda.sh` | Lambda函数调试工具 | 🔧 故障排除时 |

---

## 🚀 prepare_py311_layer.sh

### 功能说明
- **核心功能**：为Lambda构建兼容的Python 3.11依赖包Layer
- **解决问题**：平台兼容性问题（macOS ARM64 → Linux x86_64）
- **自动化**：构建、上传、更新Lambda函数

### 主要特性
✅ **平台特定安装**：确保Linux x86_64兼容性  
✅ **依赖验证**：检查关键二进制文件（pydantic_core等）  
✅ **自动部署**：上传Layer并更新Lambda函数  
✅ **状态验证**：确认函数使用正确的Layer版本  

### 使用方法
```bash
# 基本使用
./scripts/prepare_py311_layer.sh

# 保留构建文件（用于调试）
./scripts/prepare_py311_layer.sh --keep-build

# 设置不同的AWS区域
AWS_REGION=us-west-2 ./scripts/prepare_py311_layer.sh
```

### 输出示例
```
🚀 AI_MCP Lambda Layer构建脚本
基于调试指南优化，解决平台兼容性问题

📋 环境检查...
✅ Python: Python 3.11.x
✅ pip: pip 23.x.x  
✅ AWS CLI 已配置

📦 安装依赖包（Linux x86_64平台）...
解决方案：使用平台特定安装避免pydantic_core兼容性问题
✅ 依赖安装完成

🔍 验证关键二进制文件...
✅ pydantic_core 二进制文件:
   _pydantic_core.cpython-311-x86_64-linux-gnu.so
✅ 检测到正确的Linux二进制文件

☁️ 上传Layer到AWS Lambda...
✅ Layer上传成功
   版本: 21
   ARN: arn:aws:lambda:us-east-1:xxx:layer:mcp-dependencies:21

🔄 更新Lambda函数使用新Layer...
✅ mcp-order-status-server 更新成功
✅ mcp-client 更新成功

🎉 Layer构建和部署完成！
```

### 故障排除
- **权限错误**：确保AWS CLI配置正确
- **Python版本问题**：脚本会自动使用系统Python 3
- **网络问题**：检查pip源和AWS连接

---

## 🧪 test_all_apis.sh

### 功能说明
- **端到端测试**：验证所有API功能正常
- **格式验证**：检查JSON响应格式和UTF-8编码
- **性能监控**：监测API响应时间

### 测试覆盖
1. **Mock API**：订单状态查询
2. **MCP Server**：健康检查 + JSON-RPC工具调用
3. **Chatbot API**：健康检查 + AI对话功能
4. **高级验证**：响应格式、编码、性能

### 使用方法
```bash
# 运行完整测试套件
./scripts/test_all_apis.sh

# 检查jq是否安装（可选，用于JSON格式化）
brew install jq  # macOS
```

### 输出示例
```
🧪 AI_MCP项目 - 全面API测试
基于调试指南的端到端验证流程

=== 测试1: Mock API - 订单状态查询 ===
🔍 测试: Mock API订单查询
   URL: https://3kj9ouspqf.execute-api.us-east-1.amazonaws.com/dev/orders/12345
   状态码: 200
✅ HTTP状态码正确 (200)
✅ 响应为有效JSON格式
响应内容:
{
  "order_id": "12345",
  "status": "已发货，预计3天内送达"
}

=== 测试结果摘要 ===
总测试数: 8
通过测试: 8
失败测试: 0
成功率: 100%
🎉 所有测试通过！系统运行正常
```

### API端点配置
如果API端点发生变化，请修改脚本中的URL配置：
```bash
# 在脚本中更新这些URL
MOCK_API_URL="https://your-api-id.execute-api.us-east-1.amazonaws.com/dev"
MCP_SERVER_URL="https://your-api-id.execute-api.us-east-1.amazonaws.com/dev"
CHATBOT_API_URL="https://your-api-id.execute-api.us-east-1.amazonaws.com/dev"
```

---

## 🔧 debug_lambda.sh

### 功能说明
- **交互式调试**：提供菜单式问题诊断界面
- **日志分析**：自动查找和分析错误日志
- **配置检查**：验证Lambda函数和Layer配置
- **一键修复**：自动修复常见问题

### 主要功能
1. **函数配置检查**：Runtime、State、Layers、环境变量
2. **日志查看**：最近日志、错误过滤、导入错误检测
3. **Layer管理**：版本检查、兼容性验证、自动更新
4. **权限验证**：Bedrock模型访问权限测试
5. **状态同步**：Terraform状态与实际资源对比

### 使用方法
```bash
# 启动交互式调试工具
./scripts/debug_lambda.sh
```

### 菜单选项
```
🔧 AI_MCP Lambda函数调试工具
基于调试指南的问题诊断和修复

请选择操作:
1. 检查所有函数配置
2. 查看最近日志
3. 搜索错误日志
4. 检查Layer兼容性
5. 检查导入错误
6. 修复Layer问题
7. 检查Bedrock权限
8. 检查Terraform状态
9. 完整诊断（推荐）
0. 退出
```

### 常用诊断流程
1. **首次使用**：选择 `9` 进行完整诊断
2. **部署后验证**：选择 `1` 检查配置，然后 `3` 搜索错误
3. **导入错误**：选择 `5` 检查导入问题，然后 `6` 修复Layer
4. **权限问题**：选择 `7` 检查Bedrock权限

### 输出示例
```
🔍 检查Layer兼容性问题...
✅ 最新Layer版本: 21
✅ mcp-order-status-server: 使用最新Layer版本 21
✅ mcp-client: 使用最新Layer版本 21
⚠️ order_mock_api: 使用旧版本 14，最新版本: 21

🔍 检查常见导入错误...
检查 mcp-order-status-server...
检查 mcp-client...
✅ 未发现导入错误

🔍 检查Bedrock权限...
测试模型: amazon.titan-text-express-v1
✅ amazon.titan-text-express-v1: 有访问权限
测试模型: anthropic.claude-v2:1
❌ anthropic.claude-v2:1: 无访问权限
   需要在Bedrock控制台申请模型访问权限
```

---

## 🛠️ 最佳实践

### 开发工作流
```bash
# 1. 修改依赖后重新构建Layer
./scripts/prepare_py311_layer.sh

# 2. 运行完整测试验证功能
./scripts/test_all_apis.sh

# 3. 如有问题，使用调试工具
./scripts/debug_lambda.sh
```

### 故障排除工作流
```bash
# 1. 快速诊断
./scripts/debug_lambda.sh  # 选择选项9

# 2. 查看具体错误
./scripts/debug_lambda.sh  # 选择选项2或3

# 3. 尝试自动修复
./scripts/debug_lambda.sh  # 选择选项6

# 4. 验证修复效果
./scripts/test_all_apis.sh
```

### 环境变量配置
```bash
# 设置AWS区域
export AWS_REGION="us-east-1"

# 禁用AWS CLI分页器（避免shell冲突）
export AWS_PAGER=""

# 或者在运行时指定
AWS_REGION=us-west-2 ./scripts/prepare_py311_layer.sh
```

---

## 📝 注意事项

### 系统要求
- **操作系统**：macOS/Linux
- **Python**：3.8+ (推荐3.11)
- **工具依赖**：curl, aws-cli, jq(可选)

### 权限要求
- **AWS IAM权限**：Lambda、CloudWatch Logs、Bedrock访问权限
- **文件权限**：脚本具有可执行权限 (`chmod +x scripts/*.sh`)

### 安全提醒
- 脚本会自动设置 `AWS_PAGER=""` 避免shell配置冲突
- 所有AWS操作都使用当前配置的AWS凭证
- 敏感信息不会写入日志文件

---

## 🔗 相关文档

- **调试指南**：`../AI_MCP_Debugging_Guide.md` - 详细的问题解决经验
- **项目README**：`../README.md` - 项目整体说明
- **源代码**：`../src/` - Lambda函数源代码

---

## 💡 贡献指南

如需添加新功能或修复bug：

1. 基于调试指南中的经验教训
2. 保持脚本的颜色输出和用户友好性
3. 添加适当的错误处理和验证
4. 更新此README文档

---

*基于AI_MCP项目调试实战经验优化* 🚀 