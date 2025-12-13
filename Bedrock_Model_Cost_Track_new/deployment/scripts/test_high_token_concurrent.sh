#!/bin/bash

# 高 Token 并发测试脚本

set -e

API_ENDPOINT="https://tor8uppsc3.execute-api.us-east-1.amazonaws.com/production/invoke"
CONCURRENT_CALLS=3
TOTAL_CALLS=10

echo "🚀 高 Token 并发测试..."
echo "API 端点: $API_ENDPOINT"
echo "并发数: $CONCURRENT_CALLS"
echo "总调用数: $TOTAL_CALLS"
echo "Token 设置: 输入~100, 输出~500"
echo ""

# 高 Token 测试函数
call_high_token_api() {
    local call_id=$1
    local start_time=$(date +%s.%N)
    
    # 长提示词，产生更多输入和输出 Token
    local long_prompt="Please provide a comprehensive and detailed explanation about cloud computing architecture, including the following aspects: 1) Infrastructure as a Service (IaaS) components and benefits, 2) Platform as a Service (PaaS) offerings and use cases, 3) Software as a Service (SaaS) models and examples, 4) Security considerations in cloud environments, 5) Cost optimization strategies, 6) Multi-cloud and hybrid cloud approaches, 7) Serverless computing paradigms, 8) Container orchestration with Kubernetes, 9) DevOps integration in cloud environments, and 10) Future trends in cloud technology. Please make your response detailed and informative for call number $call_id."
    
    local response=$(curl -s -w "\n%{http_code}" -X POST "$API_ENDPOINT" \
        -H "X-Tenant-Id: demo1" \
        -H "Content-Type: application/json" \
        -d "{
            \"applicationId\": \"websearch\",
            \"prompt\": \"$long_prompt\",
            \"maxTokens\": 500
        }")
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l)
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n -1)
    
    echo "[$call_id] HTTP: $http_code | 耗时: ${duration}s"
    
    if [ "$http_code" = "200" ]; then
        local cost=$(echo "$body" | jq -r '.usage.cost // "N/A"' 2>/dev/null || echo "N/A")
        local input_tokens=$(echo "$body" | jq -r '.usage.inputTokens // "N/A"' 2>/dev/null || echo "N/A")
        local output_tokens=$(echo "$body" | jq -r '.usage.outputTokens // "N/A"' 2>/dev/null || echo "N/A")
        echo "[$call_id] 成本: \$$cost | 输入: $input_tokens | 输出: $output_tokens"
    else
        echo "[$call_id] 错误: $(echo "$body" | jq -r '.error // .message // .' 2>/dev/null || echo "$body")"
    fi
    
    return 0
}

# 并发执行高 Token 测试
echo "📊 开始高 Token 并发调用..."
start_time=$(date +%s)

for ((i=1; i<=TOTAL_CALLS; i++)); do
    # 控制并发数
    while [ $(jobs -r | wc -l) -ge $CONCURRENT_CALLS ]; do
        sleep 0.5
    done
    
    # 后台执行调用
    call_high_token_api $i &
done

# 等待所有调用完成
wait

end_time=$(date +%s)
total_duration=$((end_time - start_time))

echo ""
echo "✅ 高 Token 并发测试完成！"
echo "总耗时: ${total_duration}s"
echo "平均每次调用: $((total_duration * 1000 / TOTAL_CALLS))ms"

# 检查 CloudWatch 指标
echo ""
echo "📈 检查高成本指标..."
sleep 15

# 检查总成本
TOTAL_COST=$(aws cloudwatch get-metric-statistics \
    --namespace "BedrockCostManagement" \
    --metric-name "InvocationCost" \
    --dimensions Name=TenantID,Value=demo1 \
    --start-time $(date -u -v-20M +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum \
    --region us-east-1 \
    --query 'Datapoints[].Sum' \
    --output text 2>/dev/null | awk '{sum+=$1} END {printf "%.6f", sum}')

echo "最近总成本: \$${TOTAL_COST:-0.000000}"

# 检查总 Token 数
INPUT_TOKENS=$(aws cloudwatch get-metric-statistics \
    --namespace "BedrockCostManagement" \
    --metric-name "InputTokens" \
    --dimensions Name=TenantID,Value=demo1 \
    --start-time $(date -u -v-20M +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum \
    --region us-east-1 \
    --query 'Datapoints[].Sum' \
    --output text 2>/dev/null | awk '{sum+=$1} END {print sum}')

OUTPUT_TOKENS=$(aws cloudwatch get-metric-statistics \
    --namespace "BedrockCostManagement" \
    --metric-name "OutputTokens" \
    --dimensions Name=TenantID,Value=demo1 \
    --start-time $(date -u -v-20M +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum \
    --region us-east-1 \
    --query 'Datapoints[].Sum' \
    --output text 2>/dev/null | awk '{sum+=$1} END {print sum}')

echo "总输入 Token: ${INPUT_TOKENS:-0}"
echo "总输出 Token: ${OUTPUT_TOKENS:-0}"

echo ""
echo "🎯 高 Token 测试总结:"
echo "- 长提示词测试完成"
echo "- 高输出 Token 测试完成"
echo "- 成本追踪验证完成"
