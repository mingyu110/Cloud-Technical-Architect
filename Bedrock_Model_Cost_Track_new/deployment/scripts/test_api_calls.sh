#!/bin/bash

# Amazon Bedrock 多租户成本追踪系统 - API 调用完整测试脚本
# 功能：测试正常调用、预算不足、预算恢复等场景
# 用法：./test_api_calls.sh [tenant_id]

set -e

# 检查依赖
command -v aws >/dev/null 2>&1 || { echo "❌ 请先安装 AWS CLI"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "❌ 请先安装 curl"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "❌ 请先安装 jq"; exit 1; }

# 参数配置
TENANT_ID="${1:-tenant-demo1}"
REGION="us-east-1"
STACK_NAME="bedrock-cost-tracking"

echo "========================================"
echo "API 调用完整测试脚本"
echo "租户 ID: $TENANT_ID"
echo "区域: $REGION"
echo "========================================"
echo ""

# 获取 API Gateway URL
echo "🔍 获取 API Gateway URL..."
API_URL=$(aws cloudformation describe-stacks \
    --stack-name ${STACK_NAME}-apigateway \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
    --output text 2>/dev/null || echo "")

if [ -z "$API_URL" ]; then
    echo "❌ 无法获取 API Gateway URL，请确保："
    echo "   1. CloudFormation 堆栈已部署完成"
    echo "   2. 堆栈名称正确: ${STACK_NAME}-apigateway"
    exit 1
fi

echo "📍 API Gateway URL: $API_URL"
echo ""

# 检查当前预算
check_budget() {
    echo "💰 当前预算状态:"
    aws dynamodb get-item \
        --table-name bedrock-cost-tracking-production-tenant-budgets \
        --region $REGION \
        --key '{
            "tenantId": {"S": "'$TENANT_ID'"},
            "modelId": {"S": "ALL"}
        }' \
        --projection-expression "balance, totalBudget, alertThreshold" \
        --output json | jq .Item
    echo ""
}

call_api() {
    local test_name="$1"
    local payload="$2"

    echo "=== $test_name ==="

    local response=$(curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "X-Tenant-Id: $TENANT_ID" \
        -d "$payload")

    echo "请求: $payload"
    echo "响应: $response" | jq . 2>/dev/null || echo "$response"
    echo ""

    # 检查响应状态
    local http_status=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "X-Tenant-Id: $TENANT_ID" \
        -d "$payload")

    echo "HTTP 状态码: $http_status"

    # 提取成本信息
    if echo "$response" | jq -e '.cost' >/dev/null 2>&1; then
        local cost=$(echo "$response" | jq -r '.cost')
        echo "调用成本: \$$cost"
    fi

    echo "─────────────────────────────"
    echo ""
}

# 测试 1: 正常调用
echo "🧪 测试 1: 正常调用（预期成本 ~\$0.003）"
call_api "正常调用" '{
    "applicationId": "websearch",
    "model": "claude-3-haiku",
    "prompt": "What is AWS Lambda?",
    "maxTokens": 200
}'

# 等待成本处理
sleep 2
check_budget

# 测试 2: 预算不足场景
echo "🧪 测试 2: 预算不足场景"
echo "设置余额为 \$0.01..."
aws dynamodb update-item \
    --table-name bedrock-cost-tracking-production-tenant-budgets \
    --region $REGION \
    --key '{
        "tenantId": {"S": "'$TENANT_ID'"},
        "modelId": {"S": "ALL"}
    }' \
    --update-expression "SET balance = :balance" \
    --expression-attribute-values '{
        ":balance": {"N": "0.01"}
    }' >/dev/null

call_api "预算不足测试" '{
    "applicationId": "websearch",
    "model": "claude-3-sonnet",
    "prompt": "Write a detailed explanation of serverless architecture.",
    "maxTokens": 1000
}'

# 测试 3: 预算耗尽后调用
echo "🧪 测试 3: 预算耗尽后调用"
echo "设置余额为 \$0.00..."
aws dynamodb update-item \
    --table-name bedrock-cost-tracking-production-tenant-budgets \
    --region $REGION \
    --key '{
        "tenantId": {"S": "'$TENANT_ID'"},
        "modelId": {"S": "ALL"}
    }' \
    --update-expression "SET balance = :balance" \
    --expression-attribute-values '{
        ":balance": {"N": "0.00"}
    }' >/dev/null

call_api "预算耗尽测试" '{
    "applicationId": "websearch",
    "model": "claude-3-haiku",
    "prompt": "Explain cloud computing in simple terms.",
    "maxTokens": 150
}'

# 测试 4: 不同模型调用
echo "🧪 测试 4: 不同模型调用"
echo "恢复预算为 \$10.00..."
aws dynamodb update-item \
    --table-name bedrock-cost-tracking-production-tenant-budgets \
    --region $REGION \
    --key '{
        "tenantId": {"S": "'$TENANT_ID'"},
        "modelId": {"S": "ALL"}
    }' \
    --update-expression "SET balance = :balance" \
    --expression-attribute-values '{
        ":balance": {"N": "10.00"}
    }' >/dev/null

call_api "Haiku 模型调用" '{
    "applicationId": "websearch",
    "model": "claude-3-haiku",
    "prompt": "What is machine learning?",
    "maxTokens": 100
}'

call_api "Sonnet 模型调用" '{
    "applicationId": "websearch",
    "model": "claude-3-sonnet",
    "prompt": "Compare machine learning and deep learning.",
    "maxTokens": 200
}'

# 验证 CloudWatch 指标
echo "📊 验证 CloudWatch 指标..."
echo "查看 InvocationCost 指标："
aws cloudwatch get-metric-statistics \
    --namespace "BedrockCostManagement" \
    --metric-name "InvocationCost" \
    --dimensions Name=TenantID,Value=$TENANT_ID \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum \
    --region $REGION \
    --query 'Datapoints[].{Time:Timestamp,Value:Sum}' \
    --output table 2>/dev/null || echo "ℹ️  指标数据尚未显示"

# 查看 CloudWatch Logs
echo ""
echo "📝 最近的 CloudWatch 日志："
aws logs filter-log-events \
    --log-group-name /aws/lambda/bedrock-main-function \
    --region $REGION \
    --limit 3 \
    --query 'events[].{Time:timestamp,Message:message}' \
    --output table 2>/dev/null || echo "ℹ️  暂无日志"

# 最终预算状态
echo ""
echo "🎯 最终预算状态："
check_budget

echo "========================================"
echo "✅ API 调用测试完成！"
echo "========================================"
echo ""
echo "📈 总结："
echo "- 正常调用：✓ 测试完成"
echo "- 预算不足：✓ 测试完成"
echo "- 预算耗尽：✓ 测试完成"
echo "- 多模型调用：✓ 测试完成"
echo ""
echo "🔍 故障排查命令："
echo "aws logs tail /aws/lambda/bedrock-main-function --follow --region $REGION"
echo "aws logs tail /aws/lambda/bedrock-cost-function --follow --region $REGION"
echo ""
echo "下一步建议：运行 ./create_test_data.sh 恢复测试数据"