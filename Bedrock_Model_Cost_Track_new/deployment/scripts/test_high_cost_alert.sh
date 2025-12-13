#!/bin/bash

# Amazon Bedrock 多租户成本追踪系统 - 高成本调用告警测试脚本
# 功能：发送高成本调用请求并验证告警触发
# 用法：./test_high_cost_alert.sh [api_url] [tenant_id]

set -e

# 检查依赖
command -v aws >/dev/null 2>&1 || { echo "❌ 请先安装 AWS CLI"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "❌ 请先安装 curl"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "❌ 请先安装 jq"; exit 1; }

# 参数配置，支持命令行传入或自动获取
API_URL="${1:-}"
TENANT_ID="${2:-tenant-demo1}"
REGION="us-east-1"

# 如果没有提供 API_URL，尝试从 CloudFormation 获取
if [ -z "$API_URL" ]; then
    echo "🔍 尝试从 CloudFormation 获取 API Gateway URL..."
    API_URL=$(aws cloudformation describe-stacks \
        --stack-name bedrock-cost-tracking-apigateway \
        --region $REGION \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
        --output text 2>/dev/null || echo "")
fi

# 验证 API_URL
if [ -z "$API_URL" ]; then
    echo "❌ 无法获取 API Gateway URL，请："
    echo "   1. 提供参数: ./test_high_cost_alert.sh https://api-url/tenant-id"
    echo "   2. 确保 CloudFormation 堆栈部署完成"
    exit 1
fi

echo "========================================"
echo "高成本调用告警测试脚本"
echo "API URL: $API_URL"
echo "租户 ID: $TENANT_ID"
echo "区域: $REGION"
echo "========================================"
echo ""

# 创建长文本提示 - 旨在生成大量输出tokens
cat > /tmp/high_cost_prompt.txt << 'EOF'
请写一篇关于人工智能的长期影响的详细分析文章。
需要包含以下方面：
1. 对就业市场的影响（500字）
2. 对教育体系的变革（500字）
3. 对伦理和法律的挑战（500字）
4. 未来发展趋势预测（500字）
5. 技术实现路径分析（500字）
6. 社会经济效应评估（500字）
7. 政策制定建议（500字）
8. 国际合作框架（500字）

请详细阐述每个方面，总字数约 4000 字。确保文章内容深入、分析全面，提供具体的案例和数据支撑。
EOF

PROMPT=$(cat /tmp/high_cost_prompt.txt | tr '\n' ' ' | sed 's/"/\\"/g')

echo "💰 测试高成本调用告警"
echo "单次调用成本阈值: \$10.00"
echo "预期触发告警：是（长文本+高maxTokens）"
echo ""

echo "📤 发送高成本调用请求..."
echo "使用长文本提示和高 maxTokens 值来触发高成本调用"
echo ""

# 发送请求
RESPONSE=$(curl -s -X POST "$API_URL" \
    -H "Content-Type: application/json" \
    -H "X-Tenant-Id: $TENANT_ID" \
    -d "{
        \"applicationId\": \"demo-high-cost\",
        \"model\": \"claude-3-sonnet\",
        \"prompt\": \"$PROMPT\",
        \"maxTokens\": 4000
    }")

# 显示响应
echo "📥 响应内容："
echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
echo ""

# 检查响应是否包含成本信息
if echo "$RESPONSE" | jq -e '.cost' >/dev/null 2>&1; then
    COST=$(echo "$RESPONSE" | jq -r '.cost')
    echo "💵 本次调用成本: \$${COST}"

    # 计算是否超过阈值
    THRESHOLD=10
    if (( $(echo "$COST > $THRESHOLD" | bc -l) )); then
        echo "⚠️  成本超过阈值 (\$${THRESHOLD})，应触发高成本告警"
    else
        echo "ℹ️  成本未超过阈值 (\$${THRESHOLD})"
    fi
else
    echo "⚠️  响应中未找到成本信息"
fi

echo ""
echo "🔍 检查 CloudWatch Logs..."
echo "日志组: /aws/lambda/bedrock-main-function"
echo "搜索模式: 'High cost invocation detected'"
echo ""

# 等待日志写入
sleep 3

# 查询 CloudWatch Logs 中的高成本告警
echo "📋 CloudWatch Logs 查询结果："
aws logs filter-log-events \
    --log-group-name /aws/lambda/bedrock-main-function \
    --filter-pattern "High cost invocation detected" \
    --region $REGION \
    --limit 5 \
    --query 'events[].message' \
    --output text | head -10

# 如果没有找到，给出查询建议
if [ $? -ne 0 ] || [ -z "$(aws logs filter-log-events \
    --log-group-name /aws/lambda/bedrock-main-function \
    --filter-pattern "High cost invocation detected" \
    --region $REGION \
    --query 'events[].message' \
    --output text 2>/dev/null | head -1)" ]; then
    echo ""
    echo "❓ 未找到高成本告警日志，可能原因："
    echo "   1. 成本未达到阈值 (\$10)"
    echo "   2. 日志尚未写入（等待 30 秒）"
    echo "   3. 函数配置问题"
    echo ""
    echo "🛠️  手动检查建议："
    echo "   aws logs tail /aws/lambda/bedrock-main-function --follow --region $REGION"
    echo "   搜索包含 'High cost' 或 'ALERT' 的日志"
fi

# 验证 CloudWatch Metrics
echo ""
echo "📊 检查 CloudWatch 指标..."
aws cloudwatch list-metrics \
    --namespace "BedrockCostManagement" \
    --region $REGION \
    --metric-name "InvocationCost" \
    --dimensions Name=TenantID,Value=$TENANT_ID \
    --output table 2>/dev/null || echo "ℹ️  指标尚未显示（可能需要几分钟）"

# 清理临时文件
rm -f /tmp/high_cost_prompt.txt

echo ""
echo "========================================"
echo "✅ 高成本调用测试完成！"
echo "========================================"
echo ""
echo "下一步建议："
echo "1. 检查 Lambda 函数日志中的详细成本信息"
echo "2. 验证高成本告警是否正常工作"
echo "3. 运行 ./test_api_calls.sh 测试其他 API 场景"
echo ""
echo "CloudWatch Logs Insights 查询语句："
echo "fields @timestamp, @message | filter @message like /High cost invocation detected/"
echo ""}