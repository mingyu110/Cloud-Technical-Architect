# AI_MCP 项目

基于AWS BedRock、AWS Lambda、AWS API Gateway和MCP打造的客户支持聊天机器人系统。

## 项目结构

```
AI_MCP
├── docs                      # 项目文档
├── infrastructure            # 基础设施代码
│   ├── modules               # Terraform模块
│   │   ├── api_gateway       # API Gateway模块
│   │   └── lambda            # Lambda模块
│   └── terraform             # Terraform主配置
├── scripts                   # 辅助脚本
├── src                       # 源代码
│   ├── lambda                # Lambda函数代码
│   │   ├── mcp_client        # MCP客户端，集成Bedrock
│   │   ├── mcp_server        # MCP服务器
│   │   └── order_mock_api    # 订单状态模拟API
│   ├── mcp_server            # MCP服务器实现
│   └── tests                 # 测试代码
└── requirements.txt          # 项目依赖
```

## 组件说明

### 1. 订单状态模拟API (order_mock_api)

- 功能：模拟订单数据库API，返回订单状态信息
- 技术：AWS Lambda + API Gateway
- 接口：接收订单ID，返回订单状态

### 2. MCP服务器 (mcp_server)

- 功能：实现MCP (Model Control Protocol) 服务器，提供订单查询工具
- 技术：AWS Lambda + API Gateway + FastMCP框架
- 工具：get_order_status - 获取订单状态

### 3. MCP客户端 (mcp_client)

- 功能：集成AWS Bedrock，处理用户查询，调用MCP服务器
- 技术：AWS Lambda + API Gateway + AWS Bedrock + MCP Client SDK
- 处理：解析用户查询，提取订单信息，调用LLM生成自然语言响应

## 部署说明

### 前提条件

- AWS账户和CLI配置
- Terraform 1.0+
- Python 3.9+

### 部署步骤

1. 克隆仓库：
   ```
   git clone https://github.com/yourusername/AI_MCP.git
   cd AI_MCP
   ```

2. 安装依赖：
   ```
   pip install -r requirements.txt
   ```

3. 使用Terraform部署：
   ```
   cd infrastructure/terraform
   terraform init
   terraform plan
   terraform apply
   ```

4. 部署完成后，Terraform会输出API Gateway的URL，可以用于测试和集成。

## 使用示例

### 查询订单状态

```bash
curl -X POST https://your-api-gateway-url.amazonaws.com/dev \
  -H "Content-Type: application/json" \
  -d '{"query": "我的订单12345什么时候到？", "order_id": "12345"}'
```

响应示例：

```json
{
  "response": "您的订单12345目前状态是已发货，预计会在3-5个工作日内送达。您可以通过物流跟踪系统查看具体配送进度。"
}
```

## 开发指南

- 修改订单模拟数据：编辑 `src/lambda/order_mock_api/order_mock_api.py`
- 添加新的MCP工具：编辑 `src/lambda/mcp_server/mcp_server.py`
- 调整LLM提示模板：编辑 `src/lambda/mcp_client/mcp_client.py`

## 许可证

MIT 