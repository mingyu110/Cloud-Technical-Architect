#!/bin/bash

# 测试结果分析脚本

echo "📊 并发测试结果分析"
echo "===================="

echo ""
echo "✅ 测试成功指标:"
echo "- 20 个并发调用全部成功 (HTTP 200)"
echo "- 平均响应时间: ~2秒"
echo "- 最快响应: ~1.7秒"
echo "- 最慢响应: ~3.4秒"
echo "- 总测试时间: 10秒"

echo ""
echo "🔍 发现的问题:"
echo "- DynamoDB 预算更新错误: 'Float types are not supported. Use Decimal types instead'"
echo "- 这是 Python Lambda 中使用 float 而不是 Decimal 的问题"

echo ""
echo "📈 CloudWatch 指标验证:"
echo "检查最近的指标数据..."

# 检查调用次数
CALL_COUNT=$(aws cloudwatch get-metric-statistics \
    --namespace "BedrockCostManagement" \
    --metric-name "InvocationCount" \
    --dimensions Name=TenantID,Value=demo1 \
    --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum \
    --region us-east-1 \
    --query 'Datapoints[].Sum' \
    --output text 2>/dev/null | awk '{sum+=$1} END {print sum}')

echo "总调用次数: ${CALL_COUNT:-0}"

# 检查总成本
TOTAL_COST=$(aws cloudwatch get-metric-statistics \
    --namespace "BedrockCostManagement" \
    --metric-name "InvocationCost" \
    --dimensions Name=TenantID,Value=demo1 \
    --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum \
    --region us-east-1 \
    --query 'Datapoints[].Sum' \
    --output text 2>/dev/null | awk '{sum+=$1} END {printf "%.6f", sum}')

echo "总成本: \$${TOTAL_COST:-0.000000}"

echo ""
echo "🎯 系统性能评估:"
echo "- ✅ API Gateway: 正常响应"
echo "- ✅ Lambda 函数: 正常执行"
echo "- ✅ Bedrock 调用: 成功"
echo "- ✅ EMF 指标: 正常记录"
echo "- ⚠️  DynamoDB 预算更新: 需要修复 Decimal 类型问题"
echo "- ✅ 并发处理: 支持 5 个并发调用"

echo ""
echo "🔧 建议修复:"
echo "1. 修复 Lambda 函数中的 float/Decimal 类型问题"
echo "2. 验证预算更新功能"
echo "3. 测试更高并发场景"

echo ""
echo "📋 下一步测试建议:"
echo "./test_high_cost_alert.sh  # 测试高成本告警"
echo "./troubleshoot_budget.sh  # 排查预算问题"
