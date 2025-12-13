#!/bin/bash

# 并发 API 调用测试脚本

set -e

API_ENDPOINT="https://tor8uppsc3.execute-api.us-east-1.amazonaws.com/production/invoke"
CONCURRENT_CALLS=5
TOTAL_CALLS=20

echo "🚀 开始并发测试..."
echo "API 端点: $API_ENDPOINT"
echo "并发数: $CONCURRENT_CALLS"
echo "总调用数: $TOTAL_CALLS"
echo ""

# 创建测试函数
call_api() {
    local call_id=$1
    local start_time=$(date +%s.%N)
    
    local response=$(curl -s -w "\n%{http_code}" -X POST "$API_ENDPOINT" \
        -H "X-Tenant-Id: demo1" \
        -H "Content-Type: application/json" \
        -d "{
            \"applicationId\": \"websearch\",
            \"prompt\": \"Test call $call_id: What is cloud computing?\",
            \"maxTokens\": 50
        }")
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l)
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n -1)
    
    echo "[$call_id] HTTP: $http_code | 耗时: ${duration}s"
    
    if [ "$http_code" = "200" ]; then
        local cost=$(echo "$body" | jq -r '.usage.cost // "N/A"' 2>/dev/null || echo "N/A")
        local tokens=$(echo "$body" | jq -r '.usage.inputTokens + .usage.outputTokens // "N/A"' 2>/dev/null || echo "N/A")
        echo "[$call_id] 成本: \$$cost | 令牌: $tokens"
    else
        echo "[$call_id] 错误: $(echo "$body" | jq -r '.error // .message // .' 2>/dev/null || echo "$body")"
    fi
    
    return 0
}

# 并发执行测试
echo "📊 开始并发调用..."
start_time=$(date +%s)

for ((i=1; i<=TOTAL_CALLS; i++)); do
    # 控制并发数
    while [ $(jobs -r | wc -l) -ge $CONCURRENT_CALLS ]; do
        sleep 0.1
    done
    
    # 后台执行调用
    call_api $i &
done

# 等待所有调用完成
wait

end_time=$(date +%s)
total_duration=$((end_time - start_time))

echo ""
echo "✅ 并发测试完成！"
echo "总耗时: ${total_duration}s"
echo "平均每次调用: $((total_duration * 1000 / TOTAL_CALLS))ms"

# 检查 CloudWatch 指标
echo ""
echo "📈 检查 CloudWatch 指标..."
sleep 10

aws cloudwatch get-metric-statistics \
    --namespace "BedrockCostManagement" \
    --metric-name "InvocationCount" \
    --dimensions Name=TenantID,Value=demo1 \
    --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum \
    --region us-east-1 \
    --query 'Datapoints[].Sum' \
    --output text 2>/dev/null | xargs -I {} echo "总调用次数: {}"

aws cloudwatch get-metric-statistics \
    --namespace "BedrockCostManagement" \
    --metric-name "InvocationCost" \
    --dimensions Name=TenantID,Value=demo1 \
    --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum \
    --region us-east-1 \
    --query 'Datapoints[].Sum' \
    --output text 2>/dev/null | xargs -I {} echo "总成本: \${}"

echo ""
echo "🔍 查看最新 Lambda 日志:"
aws logs describe-log-streams \
    --log-group-name "/aws/lambda/bedrock-cost-tracking-production-main" \
    --order-by LastEventTime \
    --descending \
    --max-items 1 \
    --query 'logStreams[0].logStreamName' \
    --output text --region us-east-1 2>/dev/null | xargs -I {} \
    aws logs get-log-events \
        --log-group-name "/aws/lambda/bedrock-cost-tracking-production-main" \
        --log-stream-name {} \
        --limit 5 \
        --query 'events[].message' \
        --output text --region us-east-1 2>/dev/null || echo "无法获取日志"
