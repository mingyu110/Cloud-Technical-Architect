#!/bin/bash

# Amazon Bedrock 多租户成本追踪系统 - 创建测试数据脚本
# 功能：插入模型价格、租户配置、预算数据到 DynamoDB
# 用法：./create_test_data.sh

set -e

# 检查依赖
command -v aws >/dev/null 2>&1 || { echo "❌ 请先安装 AWS CLI"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "❌ 请先安装 jq"; exit 1; }

# 变量配置
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")

if [ -z "$ACCOUNT_ID" ]; then
    echo "❌ 无法获取 AWS 账户 ID，请检查 AWS CLI 配置"
    exit 1
fi

echo "========================================"
echo "创建测试数据脚本"
echo "区域: $REGION"
echo "账户: $ACCOUNT_ID"
echo "========================================"
echo ""

# 创建临时 model-pricing.json 文件
cat > /tmp/model-pricing.json << 'EOF'
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
EOF

# 1. 添加模型价格数据
echo "📊 添加模型价格数据..."
if aws dynamodb batch-write-item \
  --region $REGION \
  --request-items file:///tmp/model-pricing.json; then
    echo "✅ 模型价格数据添加成功"
else
    echo "❌ 模型价格数据添加失败"
    exit 1
fi

# 2. 添加租户配置
echo ""
echo "🏢 添加租户配置..."
if aws dynamodb put-item \
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
  }'; then
    echo "✅ 租户配置添加成功"
else
    echo "❌ 租户配置添加失败"
    exit 1
fi

# 3. 添加租户预算（小额预算用于演示）
echo ""
echo "💰 添加租户预算（$1.00 用于演示）..."
if aws dynamodb put-item \
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
  }'; then
    echo "✅ 租户预算添加成功"
else
    echo "❌ 租户预算添加失败"
    exit 1
fi

# 验证数据
echo ""
echo "🔍 验证数据..."
echo "模型价格记录:"
aws dynamodb scan \
  --table-name ModelPricing \
  --region $REGION \
  --select COUNT

echo ""
echo "租户配置:"
aws dynamodb get-item \
  --table-name TenantConfigs \
  --region $REGION \
  --key '{"tenantId": {"S": "tenant-demo1"}}' \
  --projection-expression "tenantId, defaultModelId, maxTokens"

echo ""
echo "租户预算:"
aws dynamodb get-item \
  --table-name TenantBudgets \
  --region $REGION \
  --key '{"tenantId": {"S": "tenant-demo1"}, "modelId": {"S": "ALL"}}' \
  --projection-expression "tenantId, balance, totalBudget"

# 清理临时文件
rm -f /tmp/model-pricing.json

echo ""
echo "========================================"
echo "✅ 测试数据创建完成！"
echo "========================================"
echo ""
echo "下一步:"
echo "1. 运行 ./test_high_cost_alert.sh 测试高成本告警"
echo "2. 运行 ./test_api_calls.sh 测试 API 调用"
echo ""