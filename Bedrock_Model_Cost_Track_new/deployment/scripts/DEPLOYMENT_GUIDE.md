# Amazon Bedrock 多租户成本追踪系统 - 部署测试文档

**版本**: 1.0
**最后更新**: 2025-11-25
**部署时间**: 2-3小时
**预计费用**: $5-10/月（不包括 Bedrock 调用成本）

---

## 目录

1. [架构总览](#架构总览)
2. [准备工作](#准备工作)
3. [自动化部署 (CloudFormation)](#自动化部署-cloudformation)
4. [手动配置步骤](#手动配置步骤)
5. [测试演示脚本](#测试演示脚本)
6. [验证清单](#验证清单)
7. [故障排查](#故障排查)

---

## 快速开始

### 脚本文件清单

本部署包已包含 **8 个可执行脚本**，可直接使用：

| 脚本文件 | 功能描述 | 使用场景 | 直接执行命令 |
|---------|----------|----------|-------------|
| `create_inference_profile.sh` | 创建 Bedrock 应用推理配置 | 部署前准备 | `./create_inference_profile.sh --tenant-id demo1` |
| `create_test_data.sh` | 插入模型价格和测试数据 | 演示前设置 | `./create_test_data.sh` |
| `test_high_cost_alert.sh` | 测试高成本调用告警 | 功能验证 | `./test_high_cost_alert.sh --api-url <URL>` |
| `test_api_calls.sh` | 测试正常调用和预算限制 | 功能验证 | `./test_api_calls.sh --api-url <URL>` |
| `troubleshoot_bedrock.sh` | 排查 Bedrock 调用失败 | 故障排查 | `./troubleshoot_bedrock.sh --tenant-id demo1` |
| `troubleshoot_budget.sh` | 排查预算不更新问题 | 故障排查 | `./troubleshoot_budget.sh` |
| `troubleshoot_metrics.sh` | 排查指标不显示问题 | 故障排查 | `./troubleshoot_metrics.sh` |
| `troubleshoot_apigateway.sh` | 排查 API Gateway 5xx 错误 | 故障排查 | `./troubleshoot_apigateway.sh` |

**脚本已添加执行权限，可直接运行**

### 快速演示流程（10 分钟）

以下演示无需部署完整 CloudFormation 堆栈，适合快速验证功能：

#### 场景 1: 预算耗尽演示（5-8 分钟）

**步骤**：

```bash
# 1. 创建少量推理配置（1 个租户）
cd deployment
./create_inference_profile.sh \
  --tenant-id tenant-quick-demo \
  --application-id websearch \
  --model claude-3-haiku

# 2. 插入小额预算（$1.00 用于快速耗尽）
./create_test_data.sh \
  --tenant-id tenant-quick-demo \
  --budget 1.0 \
  --alert-threshold 0.8

# 3. 运行预算耗尽演示（在 test/ 目录）
cd ../test
python3 demo_budget_exhaustion.py
```

**预期效果**：
- 15-20 次调用后触发 80% 预算警告
- 35-40 次调用后预算耗尽，返回 402 错误
- 验证 DynamoDB 余额递减
- 验证 Token 统计累加

---

## 架构总览

```
API Gateway
    ↓ (HTTP Request)
Main Lambda Function
    ├── 请求解析与验证
    ├── DynamoDB 租户配置查询
    ├── DynamoDB 预算检查
    ├── Resource Groups API ARN 查询
    ├── Bedrock 模型调用
    ├── CloudWatch EMF 指标记录
    ├── EventBridge 事件发布
    └── 返回响应
            ↓ (异步)
EventBridge → Cost Management Lambda
    ├── 成本计算
    ├── DynamoDB 预算更新（租户总计+模型细分）
    ├── CloudWatch EMF 指标记录
    └── SNS 告警（可选）
```

### 系统组件

| 组件 | 用途 | 服务 |
|------|------|------|
| **API 入口** | 接收租户请求 | API Gateway |
| **主函数** | 处理 Bedrock 调用 | Lambda |
| **成本管理** | 异步成本追踪 | Lambda |
| **配置存储** | 租户配置和预算 | DynamoDB |
| **事件总线** | 解耦主函数和成本管理 | EventBridge |
| **指标监控** | 实时监控和告警 | CloudWatch |
| **资源发现** | 动态查询 ARN | Resource Groups API |
| **应用推理配置** | 成本分配标签 | Bedrock |

---

## 准备工作

### 1.1 前置条件

确保满足以下条件：

- [ ] AWS 账户（具有管理员权限）
- [ ] 已启用 Amazon Bedrock（至少一个模型）
- [ ] AWS CLI 已配置（v2.x）
- [ ] Python 3.9+（用于本地测试）
- [ ] Git（克隆代码库）

### 1.2 代码下载

```bash
# 创建项目目录
mkdir bedrock-cost-tracking && cd bedrock-cost-tracking

# 下载代码（假设使用 Git）
git clone https://github.com/your-repo/bedrock-cost-tracking.git .

# 目录结构
cd bedrock-cost-tracking
ls -la
```

### 1.3 AWS CLI 配置

```bash
# 验证 AWS CLI 配置
aws configure list

# 检查 Bedrock 可用模型
aws bedrock list-foundation-models --region us-east-1 \
  --query 'modelSummaries[?providerName==`Anthropic`]' \
  --output table

# 创建 S3 存储桶（用于 CloudFormation 模板）
aws s3 mb s3://bedrock-cost-tracking-templates --region us-east-1

# 上传 CloudFormation 模板
aws s3 sync cloudformation/ s3://bedrock-cost-tracking-templates/cloudformation/
```

### 1.4 创建应用推理配置

**重要**: 每个租户需要独立的推理配置 ARN

```bash
#!/bin/bash

# 变量
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 创建租户 1 的推理配置（测试用）
TENANT1_ARN=$(aws bedrock create-inference-profile \
  --region $REGION \
  --inference-profile-name "tenant-demo1-websearch" \
  --model-source '{"copyFrom": "arn:aws:bedrock:'$REGION'::foundation-model/anthropic.claude-3-haiku-20240307-v1:0"}' \
  --tags '[
    {"key": "TenantID", "value": "tenant-demo1"},
    {"key": "ApplicationID", "value": "websearch"},
    {"key": "Environment", "value": "production"},
    {"key": "CostCenter", "value": "engineering"}
  ]' \
  --query 'inferenceProfileArn' \
  --output text)

echo "Tenant 1 ARN: $TENANT1_ARN"

# 验证创建的配置
aws bedrock list-inference-profiles \
  --region $REGION \
  --type-equals APPLICATION \
  --query 'inferenceProfileSummaries[?contains(inferenceProfileName, `tenant-demo`)].inferenceProfileArn' \
  --output table
```

---

## 自动化部署 (CloudFormation)

### 3.1 部署步骤

```bash
# 设置环境变量
export AWS_REGION="us-east-1"
export STACK_NAME="bedrock-cost-tracking"
export TEMPLATE_BUCKET="bedrock-cost-tracking-templates"

# 1. 部署 DynamoDB 表
echo "1. 部署 DynamoDB 表..."
aws cloudformation create-stack \
  --stack-name ${STACK_NAME}-dynamodb \
  --template-url https://s3.amazonaws.com/${TEMPLATE_BUCKET}/cloudformation/01-dynamodb-tables.yaml \
  --region ${AWS_REGION} \
  --capabilities CAPABILITY_NAMED_IAM

# 等待完成
aws cloudformation wait stack-create-complete \
  --stack-name ${STACK_NAME}-dynamodb \
  --region ${AWS_REGION}

# 2. 部署 IAM 角色
echo "2. 部署 IAM 角色..."
aws cloudformation create-stack \
  --stack-name ${STACK_NAME}-iam \
  --template-url https://s3.amazonaws.com/${TEMPLATE_BUCKET}/cloudformation/02-iam-roles.yaml \
  --region ${AWS_REGION} \
  --capabilities CAPABILITY_NAMED_IAM

aws cloudformation wait stack-create-complete \
  --stack-name ${STACK_NAME}-iam \
  --region ${AWS_REGION}

# 3. 部署 Lambda 函数
echo "3. 部署 Lambda 函数..."

# 首先打包 Lambda 代码
zip -r main-lambda.zip lambda_function_resource_groups.py
zip -r cost-lambda.zip lambda_function_cost_management.py

# 上传到 S3
aws s3 cp main-lambda.zip s3://${TEMPLATE_BUCKET}/lambda/main-lambda.zip
aws s3 cp cost-lambda.zip s3://${TEMPLATE_BUCKET}/lambda/cost-lambda.zip

# 部署 CloudFormation
aws cloudformation create-stack \
  --stack-name ${STACK_NAME}-lambda \
  --template-url https://s3.amazonaws.com/${TEMPLATE_BUCKET}/cloudformation/03-lambda-functions.yaml \
  --region ${AWS_REGION} \
  --parameters \
    ParameterKey=MainLambdaS3Bucket,ParameterValue=${TEMPLATE_BUCKET} \
    ParameterKey=MainLambdaS3Key,ParameterValue=lambda/main-lambda.zip \
    ParameterKey=CostLambdaS3Bucket,ParameterValue=${TEMPLATE_BUCKET} \
    ParameterKey=CostLambdaS3Key,ParameterValue=lambda/cost-lambda.zip \
  --capabilities CAPABILITY_NAMED_IAM

aws cloudformation wait stack-create-complete \
  --stack-name ${STACK_NAME}-lambda \
  --region ${AWS_REGION}

# 4. 部署监控
echo "4. 部署监控..."
aws cloudformation create-stack \
  --stack-name ${STACK_NAME}-monitoring \
  --template-url https://s3.amazonaws.com/${TEMPLATE_BUCKET}/cloudformation/04-monitoring.yaml \
  --region ${AWS_REGION}

aws cloudformation wait stack-create-complete \
  --stack-name ${STACK_NAME}-monitoring \
  --region ${AWS_REGION}

# 5. 部署 API Gateway
echo "5. 部署 API Gateway..."
aws cloudformation create-stack \
  --stack-name ${STACK_NAME}-apigateway \
  --template-url https://s3.amazonaws.com/${TEMPLATE_BUCKET}/cloudformation/05-api-gateway.yaml \
  --region ${AWS_REGION}

# 等待所有部署完成
echo "部署中，请等待 5-10 分钟..."
aws cloudformation wait stack-create-complete \
  --stack-name ${STACK_NAME}-apigateway \
  --region ${AWS_REGION}

echo "✅ 部署完成！"
```

### 3.2 CloudFormation 模板说明

#### `01-dynamodb-tables.yaml`

创建 3 张表：

1. **TenantConfigs**: 租户配置
   - PK: tenantId (String)
   - 属性: defaultModelId, allowedModels, rateLimit, maxTokens

2. **TenantBudgets**: 租户预算和统计
   - PK: tenantId, SK: modelId
   - 属性: balance, totalBudget, alertThreshold, totalCost, totalTokens
   - GSI: ModelIndex (modelId → tenantId)

3. **ModelPricing**: 模型价格
   - PK: region, SK: modelId
   - 属性: inputCost, outputCost, provider, modelName

#### `02-iam-roles.yaml`

创建 IAM 角色：

1. **MainLambdaRole**:
```yaml
Permissions:
  - bedrock:InvokeModel
  - dynamodb:GetItem, UpdateItem
  - resource-groups:GetResources
  - events:PutEvents
  - logs:CreateLogGroup, CreateLogStream, PutLogEvents
  - cloudwatch:PutMetricData
Condition:
  dynamodb:LeadingKeys: ${aws:principalTag/tenantId}
```

2. **CostLambdaRole**:
```yaml
Permissions:
  - dynamodb:UpdateItem
  - cloudwatch:PutMetricData
  - sns:Publish
  - logs:*
```

3. **EventBridgeRole**:
```yaml
TrustPolicy:
  Service: events.amazonaws.com
Permissions:
  - lambda:InvokeFunction
```

#### `03-lambda-functions.yaml`

创建 2 个 Lambda 函数：

1. **Main Lambda**:
```yaml
Properties:
  Runtime: python3.11
  Memory: 512MB
  Timeout: 30s
  Environment:
    EVENT_BUS_NAME: !Ref EventBus
    ENABLE_COST_TRACKING: true
    LOG_LEVEL: INFO
  Tags:
    Application: bedrock-cost-tracking
    Environment: production
```

2. **Cost Management Lambda**:
```yaml
Properties:
  Runtime: python3.11
  Memory: 256MB
  Timeout: 15s
  Environment:
    ALERT_TOPIC_ARN: !Ref AlertTopic
    LOG_LEVEL: INFO
```

#### `04-monitoring.yaml`

创建监控资源：

1. **EventBridge Event Bus**:
```yaml
Name: bedrock-cost-tracking-bus
EventSource: bedrock.invocation
DetailType: BedrockInvocationCost
```

2. **EventBridge Rule**:
```yaml
EventPattern:
  source:
    - bedrock.invocation
  detail-type:
    - BedrockInvocationCost
Target: CostLambdaFunction
DeadLetterQueue: SQS queue
RetryPolicy:
  MaximumRetryAttempts: 2
  MaximumEventAgeInSeconds: 3600
```

3. **CloudWatch Log Groups**:
   - `/aws/lambda/bedrock-main-function`
   - `/aws/lambda/bedrock-cost-function`

4. **SNS Topics**:
   - BudgetAlertTopic（预算告警）
   - CriticalAlertTopic（严重告警）
   - RateLimitTopic（速率限制告警）

#### `05-api-gateway.yaml`

创建 API Gateway REST API：

```yaml
Resources:
  /invoke:
    POST:
      Integration: Lambda proxy
      Authorization: None（演示用，生产建议用 Cognito 或 Lambda Authorizer）
      RateLimit: 100 req/sec（可配置）
```

### 3.3 部署验证

```bash
# 检查所有堆栈状态
aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE \
  --query 'StackSummaries[?contains(StackName, `bedrock-cost-tracking`)]' \
  --region $AWS_REGION \
  --output table

# 获取输出参数
STACK_NAME="bedrock-cost-tracking"

aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME}-apigateway \
  --region $AWS_REGION \
  --query 'Stacks[0].Outputs' \
  --output table

# 输出示例:
#| ApiGatewayUrl | https://xxxxx.execute-api.us-east-1.amazonaws.com/prod/invoke |
#| MainLambdaArn | arn:aws:lambda:us-east-1:xxxxx:function:bedrock-main |
#| CostLambdaArn | arn:aws:lambda:us-east-1:xxxxx:function:bedrock-cost |
```

---

## 手动配置步骤

### 4.1 启用 Bedrock 模型调用日志（可选）

**操作路径**: Bedrock Console → Model invocation logging → Edit

```bash
# AWS CLI 方式
aws bedrock put-model-invocation-logging-configuration \
  --region us-east-1 \
  --logging-configuration '{
    "cloudWatchConfig": {
      "logGroupName": "/aws/bedrock/model-invocations",
      "roleArn": "arn:aws:iam::ACCOUNT_ID:role/BedrockLoggingRole",
      "largeDataDeliveryS3Config": {
        "bucketName": "bedrock-logs-bucket",
        "keyPrefix": "model-logs/"
      }
    },
    "s3Config": {
      "bucketName": "bedrock-logs-bucket",
      "keyPrefix": "model-logs/"
    },
    "textDataDeliveryS3Config": {
      "bucketName": "bedrock-logs-bucket",
      "keyPrefix": "text-logs/"
    }
  }'

# 验证配置
aws bedrock get-model-invocation-logging-configuration \
  --region us-east-1
```

**注意**: 对于成本追踪，我们的方案**不依赖** Bedrock 原生日志，因为：
- 我们直接从 API 响应提取 token 用量
- 使用 EMF 格式记录指标（更实时）

### 4.2 激活成本分配标签

**操作路径**: Billing Console → Cost allocation tags → Activate

```bash
# 需要激活的标签（用于 Cost Explorer）
- TenantID
- ApplicationID
- CostCenter
- Environment

# CLI 方式激活
aws ce update-cost-allocation-tags-status \
  --cost-allocation-tags-status '{
    "costAllocationTagsStatus": [
      {"tagKey": "TenantID", "status": "Active"},
      {"tagKey": "ApplicationID", "status": "Active"},
      {"tagKey": "CostCenter", "status": "Active"},
      {"tagKey": "Environment", "status": "Active"}
    ]
  }'
```

**重要**:
- 标签激活需要 **24-48 小时** 生效
- 历史数据不追溯
- 不影响 EMF 指标（EMF 立即可用）

### 4.3 创建测试数据

```bash
#!/bin/bash

REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 1. 添加模型价格数据
echo "添加模型价格数据..."
aws dynamodb batch-write-item \
  --region $REGION \
  --request-items file://data/model-pricing.json

# model-pricing.json 示例:
{
  "RequestItems": {
    "ModelPricing": [
      {
        "PutRequest": {
          "Item": {
            "region": {"S": "us-east-1"},
            "modelId": {"S": "anthropic.claude-3-haiku-20240307-v1:0"},
            "inputCost": {"N": "0.25"},
            "outputCost": {"N": "1.25"},
            "currency": {"S": "USD"},
            "effectiveDate": {"N": "1704067200000"},
            "provider": {"S": "Anthropic"},
            "modelName": {"S": "Claude 3 Haiku"}
          }
        }
      },
      {
        "PutRequest": {
          "Item": {
            "region": {"S": "us-east-1"},
            "modelId": {"S": "anthropic.claude-3-sonnet-20240229-v1:0"},
            "inputCost": {"N": "3.00"},
            "outputCost": {"N": "15.00"},
            "currency": {"S": "USD"},
            "effectiveDate": {"N": "1704067200000"},
            "provider": {"S": "Anthropic"},
            "modelName": {"S": "Claude 3 Sonnet"}
          }
        }
      }
    ]
  }
}

# 2. 添加租户配置
echo "添加租户配置..."
aws dynamodb put-item \
  --region $REGION \
  --table-name TenantConfigs \
  --item '{
    "tenantId": {"S": "tenant-demo1"},
    "defaultModelId": {"S": "anthropic.claude-3-haiku-20240307-v1:0"},
    "allowedModels": {"L": [{"S": "claude-3-haiku"}, {"S": "claude-3-sonnet"}]},
    "maxTokens": {"N": "4000"},
    "rateLimit": {"N": "100"},
    "createdAt": {"N": "1706188800000"},
    "updatedAt": {"N": "1706188800000"}
  }'

# 3. 添加租户预算（小额预算用于演示）
echo "添加租户预算（$1.00 用于演示）..."
aws dynamodb put-item \
  --region $REGION \
  --table-name TenantBudgets \
  --item '{
    "tenantId": {"S": "tenant-demo1"},
    "modelId": {"S": "ALL"},
    "balance": {"N": "1.00"},
    "totalBudget": {"N": "1.00"},
    "alertThreshold": {"N": "0.8"},
    "isActive": {"BOOL": true},
    "resetCycle": {"S": "monthly"},
    "lastUpdated": {"N": "1706188800000"},
    "lastReset": {"N": "1706188800000"}
  }'

echo "✅ 测试数据创建完成！"
```

---

## 测试演示脚本

### 5.1 演示 1: 预算耗尽测试

```bash
# 进入测试目录
cd test/

# 安装依赖
pip install boto3 requests

# 执行演示脚本
python3 demo_budget_exhaustion.py
```

**预期输出**:

```
======================================================
Amazon Bedrock 多租户成本追踪 - 预算耗尽演示
======================================================

💰 预估成本:
   Clau-3-Haiku: $0.00025/1K输入 + $0.00125/1K输出
   典型 100输入+200输出: $0.000275/次
   40 次调用: $0.011

按 Enter 键开始演示...

🎯 步骤 1: 设置小额预算 ($1.00)
✅ 预算设置成功: $1.00

📊 初始状态:
   余额: $1.0000
   已调用次数: 0
   累计成本: $0.0000

🔄 步骤 2: 连续调用（每次成本约 $0.003）

⏱️  第 1 次调用... ✅ 成功 (成本: $0.0032)
...
⏱️  第 15 次调用... ✅ 成功 (成本: $0.0031)

🚨 预算告警触发！已使用 80.1%
   触发条件: balance < $0.20
   剩余余额: $0.1942

⏱️  第 16 次调用... ✅ 成功 (成本: $0.0029)
...
⏱️  第 35 次调用... ✅ 成功 (成本: $0.0033)

🚫 预算耗尽！

📉 预算耗尽详情:
   总调用次数: 35
   总成本: $0.1120
   平均单次成本: $0.0032

📊 最终状态:
   余额: $0.0000
   总调用次数: 35
   累计成本: $0.1120

======================================================
✅ 演示完成！
======================================================
```

### 5.2 演示 2: 高成本调用告警测试

```bash
#!/bin/bash

API_URL="https://xxxxx.execute-api.us-east-1.amazonaws.com/prod/invoke"
TENANT_ID="tenant-demo1"

echo "测试高成本调用告警..."
echo "单次调用成本阈值: $10.00"
echo ""

# 使用长文本和高 maxTokens 来触发高成本
PROMPT=$(cat <<EOF
请写一篇关于人工智能的长期影响的详细分析文章。
需要包含以下方面：
1. 对就业市场的影响（500字）
2. 对教育体系的变革（500字）
3. 对伦理和法律的挑战（500字）
4. 未来发展趋势预测（500字）
请详细阐述，总字数约 2000 字。
EOF
)

echo "发送高成本调用请求..."
echo ""

curl -X POST $API_URL \
  -H "Content-Type: application/json" \
  -H "X-Tenant-Id: $TENANT_ID" \
  -d "{
    \"applicationId\": \"demo-high-cost\",
    \"model\": \"claude-3-sonnet\",
    \"prompt\": \"$PROMPT\",
    \"maxTokens\": 4000
  }" | jq .

echo ""
echo "检查 CloudWatch Logs:"
echo "Log Group: /aws/lambda/bedrock-main-function"
echo "搜索: 'High cost invocation detected'"
```

**验证高成本告警**:

```bash
# 查看 CloudWatch Logs
aws logs filter-log-events \
  --log-group-name /aws/lambda/bedrock-main-function \
  --filter-pattern "High cost invocation detected" \
  --region us-east-1 \
  --query 'events[0].message' \
  --output text

# 预期输出:
{"level": "ALERT", "message": "High cost invocation detected", "tenantId": "tenant-demo1", "cost": 12.34, "threshold": 10.0, "timestamp": 1706188800}
```

### 5.3 演示 3: CloudWatch Dashboard 验证

```bash
# 查询 EMF 指标
aws cloudwatch list-metrics \
  --namespace "BedrockCostManagement" \
  --region us-east-1 \
  --output table

# 查询特定租户的指标
aws cloudwatch get-metric-statistics \
  --namespace "BedrockCostManagement" \
  --metric-name "InvocationCost" \
  --dimensions Name=TenantID,Value=tenant-demo1 \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Sum \
  --region us-east-1

# 使用 CloudWatch Logs Insights 查询
aws logs start-query \
  --log-group-name /aws/lambda/bedrock-main-function \
  --query-string '
    fields @timestamp, TenantID, ApplicationID, InvocationCost
    | filter InvocationCost > 0
    | stats sum(InvocationCost) as TotalCost, sum(InvocationCount) as TotalCalls by TenantID
    | sort TotalCost desc
  ' \
  --start-time $(date -u -d '1 day ago' +%s000) \
  --end-time $(date -u +%s000) \
  --region us-east-1
```

### 5.4 API 调用示例

```bash
#!/bin/bash

API_URL=$(aws cloudformation describe-stacks \
  --stack-name bedrock-cost-tracking-apigateway \
  --region us-east-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
  --output text)

echo "API Gateway URL: $API_URL"
echo ""

# 测试 1: 正常调用（成本 ~$0.003）
echo "=== 测试 1: 正常调用 ==="
curl -X POST $API_URL \
  -H "Content-Type: application/json" \
  -H "X-Tenant-Id: tenant-demo1" \
  -d '{
    "applicationId": "websearch",
    "model": "claude-3-haiku",
    "prompt": "What is AWS Lambda?",
    "maxTokens": 200
  }' | jq .

echo ""

# 测试 2: 预算不足（先设置低预算）
echo "=== 测试 2: 预算不足场景 ==="

# 设置余额为 $0.01
aws dynamodb update-item \
  --region us-east-1 \
  --table-name TenantBudgets \
  --key '{
    "tenantId": {"S": "tenant-demo1"},
    "modelId": {"S": "ALL"}
  }' \
  --update-expression "SET balance = :balance" \
  --expression-attribute-values '{
    ":balance": {"N": "0.01"}
  }'

# 尝试调用（成本 > $0.01）
curl -X POST $API_URL \
  -H "Content-Type: application/json" \
  -H "X-Tenant-Id: tenant-demo1" \
  -d '{
    "applicationId": "websearch",
    "model": "claude-3-sonnet",
    "prompt": "Write a detailed explanation of serverless architecture.",
    "maxTokens": 1000
  }' | jq .

echo ""

# 恢复预算
aws dynamodb update-item \
  --region us-east-1 \
  --table-name TenantBudgets \
  --key '{
    "tenantId": {"S": "tenant-demo1"},
    "modelId": {"S": "ALL"}
  }' \
  --update-expression "SET balance = :balance" \
  --expression-attribute-values '{
    ":balance": {"N": "100.00"}
  }'

echo "✅ 预算已恢复"
```

---

## 验证清单

### 6.1 部署验证

- [ ] DynamoDB 表创建成功（3 张表）
- [ ] IAM 角色创建成功（3 个角色）
- [ ] Lambda 函数部署成功（2 个函数）
- [ ] API Gateway 部署成功并获取 URL
- [ ] EventBridge Event Bus 和 Rule 创建成功
- [ ] CloudWatch Log Groups 创建成功
- [ ] SNS Topics 创建成功

### 6.2 功能验证

- [ ] Bedrock 模型调用成功
- [ ] Token 用量正确提取
- [ ] 成本计算准确（与 AWS 账单对比）
- [ ] DynamoDB 预算正确扣除
- [ ] EMF 指标成功记录到 CloudWatch
- [ ] EventBridge 事件正确传递
- [ ] 高成本调用告警触发（>$10）
- [ ] 预算超支时返回 402 错误

### 6.3 监控验证

- [ ] CloudWatch Dashboard 显示数据
- [ ] TenantID 维度正确分组
- [ ] InvocationCost 指标准确
- [ ] HighCostInvocation 告警触发
- [ ] SNS 通知发送成功

### 6.4 性能验证

- [ ] p95 响应时间 < 3 秒
- [ ] 冷启动时间 < 1 秒
- [ ] DynamoDB 查询 < 50ms
- [ ] 成本管理异步延迟 < 1 秒

---

## 故障排查

### 7.1 Bedrock 调用失败

**症状**: `403 Forbidden` 或 `Model not available`

**排查步骤**:
```bash
# 1. 检查 IAM 权限
aws lambda get-policy \
  --function-name bedrock-main-function \
  --region us-east-1

# 2. 检查模型是否在区域中可用
aws bedrock list-foundation-models \
  --region us-east-1 \
  --query 'modelSummaries[?modelId==`anthropic.claude-3-haiku-20240307-v1:0`]'

# 3. 检查推理配置 ARN 是否正确
aws bedrock list-inference-profiles \
  --region us-east-1 \
  --query 'inferenceProfileSummaries[?contains(inferenceProfileName, `tenant-demo`)]'

# 4. 查看 CloudWatch Logs
aws logs tail /aws/lambda/bedrock-main-function \
  --follow \
  --region us-east-1
```

**解决方案**:
- 确认在 Bedrock Console 启用所需模型
- 检查 IAM 策略包含 `bedrock:InvokeModel`
- 验证推理配置 ARN 格式正确

### 7.2 预算不更新

**症状**: 调用成功但 DynamoDB 余额未变化

**排查步骤**:
```bash
# 1. 检查 IAM 权限
aws iam get-role-policy \
  --role-name BedrockCostManagementRole \
  --policy-name DynamoDBUpdatePolicy

# 2. 检查 DynamoDB 表结构
aws dynamodb describe-table \
  --table-name TenantBudgets \
  --region us-east-1 \
  --query 'Table.KeySchema'

# 3. 手动测试更新
aws dynamodb update-item \
  --table-name TenantBudgets \
  --key '{"tenantId": {"S": "tenant-demo1"}, "modelId": {"S": "ALL"}}' \
  --update-expression "SET balance = balance - :cost" \
  --expression-attribute-values '{":cost": {"N": "0.01"}}' \
  --return-values ALL_NEW \
  --region us-east-1

# 4. 检查 EventBridge 事件传递
aws events list-rule-names-by-target \
  --target-arn arn:aws:lambda:us-east-1:ACCOUNT_ID:function:bedrock-cost-function
```

**解决方案**:
- 检查 Lambda 环境变量 `EVENT_BUS_NAME`
- 验证 EventBridge Rule 目标配置正确
- 查看 Dead Letter Queue 是否有失败事件

### 7.3 指标不显示

**症状**: CloudWatch Metrics 中没有数据

**排查步骤**:
```bash
# 1. 检查 EMF 日志格式
aws logs filter-log-events \
  --log-group-name /aws/lambda/bedrock-main-function \
  --filter-pattern '{$.Namespace = "BedrockCostManagement"}' \
  --region us-east-1 \
  --limit 1

# 2. 检查命名空间
aws cloudwatch list-metrics \
  --namespace "BedrockCostManagement" \
  --region us-east-1

# 3. 检查维度
aws cloudwatch get-metric-data \
  --metric-data-queries '{
    "Id": "m1",
    "MetricStat": {
      "Metric": {
        "Namespace": "BedrockCostManagement",
        "MetricName": "InvocationCost",
        "Dimensions": [{"Name": "TenantID", "Value": "tenant-demo1"}]
      },
      "Period": 300,
      "Stat": "Sum"
    }
  }' \
  --start-time $(date -u -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --region us-east-1
```

**解决方案**:
- 确认 Lambda 有权限 `logs:CreateLogGroup`
- 检查 CloudWatch Logs 中 EMF 格式正确
- 等待 5-10 分钟（EMF 指标提取延迟）

### 7.4 高成本告警不触发

**症状**: 调用成本 >$10 但没有告警日志

**排查步骤**:
```bash
# 1. 检查 high-cost 函数是否调用
aws logs filter-log-events \
  --log-group-name /aws/lambda/bedrock-main-function \
  --filter-pattern "log_high_cost_alert" \
  --region us-east-1

# 2. 检查条件是否正确
# 在 CloudWatch Logs Insights 中:
fields @timestamp, @message
| filter actualCost > 10
| parse @message "*ActualCost*" as cost
| display cost, tenantId

# 3. 手动调用高成本测试
# 使用长文本和高 maxTokens
```

**解决方案**:
- `lambda_function_resource_groups.py:423` 确保 `log_high_cost_alert()` 被调用
- 检查阈值是否正确传递（默认 $10）

### 7.5 API Gateway 5xx 错误

**症状**: 调用返回 `502 Bad Gateway` 或 `504 Gateway Timeout`

**排查步骤**:
```bash
# 1. 检查 API Gateway 日志
aws logs filter-log-events \
  --log-group-name API-Gateway-Execution-Logs_xxxxx/prod \
  --region us-east-1

# 2. 检查 Lambda 超时设置
aws lambda get-function-configuration \
  --function-name bedrock-main-function \
  --region us-east-1 \
  --query '{Timeout: Timeout, Memory: MemorySize}'

# 3. 测试 Lambda 单独调用
aws lambda invoke \
  --function-name bedrock-main-function \
  --payload '{"tenantId": "tenant-demo1", "prompt": "test"}' \
  --region us-east-1 \
  response.json
```

**解决方案**:
- Lambda 超时增加到 30 秒（Bedrock 调用可能耗时）
- API Gateway 超时同样设置为 30 秒
- 检查 Lambda 内存是否足够（建议 512MB+）

---

## 成本优化建议

| 优化项 | 配置前 | 配置后 | 节省 |
|--------|--------|--------|------|
| Lambda 内存 | 1024MB | 512MB | 50% |
| DynamoDB | 按需模式 | 按需模式 | - |
| CloudWatch Logs | 保留 3 个月 | 保留 1 个月 | 66% |
| EventBridge | 默认 | 无需优化 | - |
| Bedrock | 无缓存 | 实现响应缓存 | 30-50% |

**月度成本预估 (1000次调用/天)**:
- Lambda: $15-20
- DynamoDB: $5-10
- CloudWatch: $10-15
- Bedrock (Haiku): $250-300
- **总计**: $280-345

---

## 安全最佳实践

### 最低权限原则

1. **Lambda 执行角色**: 仅授予必要权限
2. **DynamoDB**: 使用 `LeadingKeys` 条件限制租户访问
3. **API Gateway**: 生产环境启用 Lambda Authorizer 或 Cognito
4. **Secrets**: 使用 AWS Secrets Manager 存储敏感配置

### 数据加密

1. **传输加密**: 所有通信使用 TLS 1.2+
2. **静态加密**: DynamoDB 和 S3 启用 KMS 加密
3. **密钥管理**: 使用 AWS 托管密钥或客户托管密钥

### 网络隔离

1. **VPC（可选）**: 将 Lambda 放入私有子网
2. **安全组**: 限制出站流量仅允许必要服务
3. **VPC 端点**: 为 DynamoDB、S3 创建 VPC 端点

---

## AWS 控制台查看指南

在脚本测试后，可以在 AWS Management Console 中查看关键数据验证系统行为：

### 7.1 DynamoDB 控制台查看

**查看路径**: DynamoDB → Tables → TenantBudgets → Items

**展示内容**: 租户预算状态和Token统计

```
TenantBudgets Table:
┌─────────────┬─────────┬──────────┬──────────────┬────────────────┐
│ tenantId    │ modelId │ balance  │ totalCost    │ totalInputTokens│
├─────────────┼─────────┼──────────┼──────────────┼────────────────┤
│ tenant-demo1│ ALL     │ $45.23   │ $954.77      │ 1,234,567      │
│ tenant-demo1│ haiku   │ -        │ $123.45      │ 156,789        │
│ tenant-demo1│ sonnet  │ -        │ $831.32      │ 1,077,778      │
└─────────────┴─────────┴──────────┴──────────────┴────────────────┘
```

**关键验证点**:
- ✓ `balance` 是否正确递减（每次调用后减少）
- ✓ `totalCost` 是否等于 `totalBudget - balance`
- ✓ `totalInputTokens` 和 `totalOutputTokens` 是否累加
- ✓ 模型细分（haiku, sonnet）的 `cumulativeCost` 是否正确

**演示操作**:
1. 在演示前截图记录初始余额
2. 运行几次调用后刷新 Items
3. 观察余额和 Token 统计的变化
4. 验证数学计算：cost = (inputTokens/1M × inputCost) + (outputTokens/1M × outputCost)

---

### 7.2 CloudWatch Logs 查看

**查看路径**: CloudWatch → Logs → Log groups → `/aws/lambda/bedrock-main-function`

#### 搜索模式 1: 查看所有调用成本

在 Logs → Log groups 中选择日志组，使用 CloudWatch Logs Insights：

```sql
fields @timestamp, TenantID, ApplicationID, ModelID, InvocationCost, InputTokens, OutputTokens
| filter InvocationCost > 0
| sort @timestamp desc
| limit 50
```

**展示示例**:
```
@timestamp          | TenantID    | ModelID        | InvocationCost | InputTokens | OutputTokens
--------------------|-------------|----------------|----------------|-------------|-------------
2025-01-25 10:00:01 | tenant-demo | claude-3-haiku | 0.0032         | 100         | 180
2025-01-25 10:00:03 | tenant-demo | claude-3-sonnet| 0.0345         | 200         | 350
2025-01-25 10:00:04 | tenant-demo | claude-3-haiku | 0.0028         | 95          | 165
```

**演示点**: 每次调用都有完整的成本追踪记录

---

#### 搜索模式 2: 查看高成本调用告警

在 Logs → Log groups 中搜索文本：

```
搜索词: "High cost invocation detected"
```

**展示示例**:
```json
{
  "level": "ALERT",
  "message": "High cost invocation detected",
  "tenantId": "tenant-demo1",
  "cost": 12.34,
  "threshold": 10.0
}
```

**演示点**: 单次调用成本 > $10 会记录告警日志

---

#### 搜索模式 3: 查看预算耗尽日志

```sql
fields @timestamp, @message
| filter @message like /Budget exceeded/
| sort @timestamp desc
```

**展示示例**:
```
@timestamp          | @message
--------------------|------------------------------
2025-01-25 10:05:01 | {"error": "Budget exceeded", "tenantId": "tenant-demo", "balance": 0.02, "estimatedCost": 0.03}
```

**演示点**: 余额不足时系统正确拒绝调用

---

### 7.3 CloudWatch Metrics 查看

**查看路径**: CloudWatch → Metrics → All metrics → BedrockInvocationTracking

#### 图表 1: 租户成本排行榜（Top 10）

**配置步骤**:

1. 选择命名空间: `BedrockInvocationTracking`
2. 选择指标: `InvocationCost`
3. 选择统计: `Sum`
4. 选择周期: `5 minutes`
5. 添加维度: `TenantID`
6. 图表类型: `Number`
7. 排序方式: 按 `Sum(InvocationCost)` 降序

**展示效果**:
```
租户成本排行榜（最近 5 分钟）

🥇 tenant-001: $23.45
🥈 tenant-002: $18.32
🥉 tenant-003: $12.67
   tenant-004: $8.91
   tenant-005: $5.43
   ...
```

**演示点**: 实时展示各租户成本排名，支持多维度分析

---

#### 图表 2: 时间序列成本趋势

**配置步骤**:

1. 选择指标: `InvocationCost (Sum)`
2. 添加维度: `TenantID = tenant-demo1`
3. 图表类型: `Line`
4. 时间范围: `1 hour`
5. 周期: `1 minute`

**展示效果**:
```
成本趋势（租户: tenant-demo1）

$0.04 ┤        ╭─────
$0.03 ┤    ╭───╯
$0.02 ┤  ╭─╯
$0.01 ┤─╯
     └─────────────
     10:00  10:15  10:30  10:45  11:00
```

**演示点**: 展示成本随时间的变化，识别高峰时段

---

#### 图表 3: 模型成本分布

**配置步骤**:

1. 选择指标: `InvocationCost (Sum)`
2. 添加维度: `ModelID`
3. 图表类型: `Pie chart`
4. 时间范围: `1 hour`

**展示效果**:
```
模型成本分布

Claude-3-Sonnet: 65% ┤███████████████████████████████████
Claude-3-Haiku:  30% ┤███████████████▌
Nova-Pro:         5% ┤███
```

**演示点**: 展示不同模型的成本占比，帮助选择经济模型

---

### 7.4 EventBridge 事件查看

**查看路径**: EventBridge → Event buses → bedrock-cost-tracking-bus → Rules

**查看内容**:

1. **Event pattern 匹配**: 确认 Rule 配置正确
```json
{
  "source": ["bedrock.invocation"],
  "detail-type": ["BedrockInvocationCost"]
}
```

2. **Rule targets**: 确认指向 cost lambda
```
Target: arn:aws:lambda:us-east-1:xxx:function:bedrock-cost-function
```

3. **Dead letter queue**: CloudWatch → EventBridge → Dead-letter queues
- 查看是否有失败事件
- 正常情况应该为 0

**演示点**: 事件正确路由到成本管理 Lambda

---

### 7.5 Lambda 监控

**查看路径**: Lambda → Functions → bedrock-main-function → Monitoring

**关键指标**:

#### 调用次数和延迟
```
Invocations (最近 1 小时)
50 ┤                ╭───╮
   │            ╭───╯   ╰───╮
25 ┤          ╭─╯           ╰──
   │      ╭───╯
 0 ┤──────╯
   └────────────────────────────
   可观察: p95 Duration = 2.3s
```

**演示点**:
- 平均延迟 < 2 秒
- p95 延迟 < 3 秒（目标）
- 冷启动影响：Init Duration

---

#### 错误率监控
```
Error rate (最近 1 小时)
1% ┤
   │
0  ┤████████████████════════════
```

**演示点**: 预算耗尽时返回的 402 错误不会显示为 Lambda Error（正确行为）

---

### 7.6 API Gateway 监控

**查看路径**: API Gateway → APIs → bedrock-api → Dashboard

**展示指标**:

| 指标 | 健康值 | 观察点 |
|------|--------|--------|
| 请求次数 | > 0 | 是否有流量 |
| 延迟 (p50) | < 2s | 响应时间是否可接受 |
| 4xx 错误率 | < 1% | 预算耗尽返回 402 |
| 5xx 错误率 | 0% | Lambda 异常 |

**演示点**:
- 4xx 错误率上升说明有租户预算耗尽（正常现象）
- 5xx 错误率上升说明系统异常

---

### 7.7 Cost Explorer 查看（24-48小时后）

**查看路径**: Billing → Cost Management → Cost Explorer

**演示内容**（标签激活后）:

```
Group by: Tags → costCenter
Service: Amazon Bedrock
Date range: This month

销售部门: $543.21
工程部门: $1,234.56
客服部门: $345.67
```

**演示点**: 基于标签的成本分配（需等待标签激活）

---

## 演示验证检查表（控制台查看）

### 演示前准备
- [ ] 在 DynamoDB 设置小额预算（$1-5）
- [ ] 在 Lambda 代码中设置 `LOG_LEVEL=INFO`
- [ ] 确保 CloudWatch Logs 保留期 ≥ 7 天

### 演示中验证

#### DynamoDB 数据验证
- [ ] 初始余额: $_____
- [ ] 调用 10 次后余额: $_____（预期: 减少）
- [ ] 预算耗尽后余额: $0.00
- [ ] Token 统计累加（Input/Output tokens 增加）
- [ ] 模型细分正确（haiku vs sonnet 成本分开统计）

#### CloudWatch Logs 验证
- [ ] 每条日志包含 InvocationCost 字段
- [ ] 每次调用显示完整的请求和响应
- [ ] 预算耗尽时显示 "Budget exceeded" 告警
- [ ] 高成本调用（>$10）显示 "High cost invocation" 告警

#### CloudWatch Metrics 验证
- [ ] Metrics 命名空间: BedrockInvocationTracking
- [ ] TenantID 维度分组正确（能看到不同租户）
- [ ] 实时指标延迟 < 1 分钟
- [ ] 成本计算准确（与 DynamoDB balance 变化一致）

#### EventBridge 验证
- [ ] Event bus: bedrock-cost-tracking-bus 存在
- [ ] Rule: 正确匹配 bedrock.invocation
- [ ] Target: 指向 cost management Lambda
- [ ] DLQ: 无失败消息（正常应为空）

### 演示后清理
- [ ] 重置测试租户预算（避免持续告警）
- [ ] 检查 Lambda 错误率（应 < 1%）
- [ ] 删除或归档 CloudWatch Logs（节省成本）

---

## 扩展和定制

编辑 `cloudformation/04-monitoring.yaml`，添加新告警：

```yaml
HighTokenUsageAlarm:
  Type: AWS::CloudWatch::Alarm
  Properties:
    AlarmName: HighTokenUsageAlert
    MetricName: OutputTokens
    Namespace: BedrockCostManagement
    Statistic: Sum
    Period: 300
    EvaluationPeriods: 1
    Threshold: 10000
    ComparisonOperator: GreaterThanThreshold
    AlarmActions:
      - !Ref AlertTopic
```

---

## 参考资料

### AWS 文档

- [Amazon Bedrock 多租户成本分配](https://aws.amazon.com/cn/blogs/machine-learning/track-allocate-and-manage-your-generative-ai-cost-and-usage-with-amazon-bedrock/)
- [Embedded Metric Format](https://docs.aws.amazon.com/zh_cn/AmazonCloudWatch/latest/monitoring/CloudWatch_Embedded_Metric_Format.html)
- [Resource Groups API](https://docs.aws.amazon.com/zh_cn/resourcegroupstagging/latest/APIReference/API_GetResources.html)
- [Lambda 并发模型](https://docs.aws.amazon.com/lambda/latest/dg/lambda-concurrency.html)
- [EventBridge 事件可靠性](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-service-level.html)

### 最佳实践

- [AWS Well-Architected Framework - Serverless](https://aws.amazon.com/blogs/apn/the-5-pillars-of-the-aws-well-architected-framework/)
- [Lambda 最佳实践](https://docs.aws.amazon.com/lambda/latest/operatorguide/)
- [DynamoDB 设计模式](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/BestPractices.html)
- [成本优化指南](https://aws.amazon.com/cost-management/)

---

## 总结

本部署测试文档提供了：

1. **完整的 CloudFormation 自动化部署流程**（2-3小时）
2. **手动配置步骤**（应用推理配置、标签激活）
3. **三种演示脚本**：
   - 预算耗尽演示（快速见效）
   - 高成本调用告警
   - CloudWatch Dashboard 验证
4. **详细的验证清单**（部署、功能、监控）
5. **故障排查指南**（常见问题 + 解决方案）

**推荐阅读顺序**: 准备工作 → 自动化部署 → 手动配置 → 测试演示 → 验证清单

**预计演示时间**: 30-45 分钟（包含部署验证）

---

