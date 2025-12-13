#!/bin/bash

# Amazon Bedrock 多租户成本追踪系统 - 指标不显示排查脚本
# 功能：诊断 EMF 格式、CloudWatch Metrics、维度配置等问题
# 用法：./troubleshoot_metrics.sh [tenant_id] [region]

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查依赖
command -v aws >/dev/null 2>&1 || { echo -e "${RED}❌ 请先安装 AWS CLI${NC}"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo -e "${RED}❌ 请先安装 jq${NC}"; exit 1; }

# 参数配置
TENANT_ID="${1:-tenant-demo1}"
REGION="${2:-us-east-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
METRICS_NAMESPACE="BedrockCostManagement"

if [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ 无法获取 AWS 账户 ID，请检查 AWS CLI 配置${NC}"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}指标不显示排查脚本${NC}"
echo -e "${BLUE}租户 ID: $TENANT_ID${NC}"
echo -e "${BLUE}区域: $REGION${NC}"
echo -e "${BLUE}账户: $ACCOUNT_ID${NC}"
echo -e "${BLUE}指标命名空间: $METRICS_NAMESPACE${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 1. 检查 Lambda 日志中的 EMF 格式
echo -e "${YELLOW}🔍 步骤 1: 检查 EMF 日志格式${NC}"
echo "在 Lambda 日志中查找 EMF 格式的指标..."

# 检查主函数的 EMF 日志
MAIN_LOG_GROUP="/aws/lambda/bedrock-main-function"
echo "主函数日志组: $MAIN_LOG_GROUP"

if aws logs describe-log-groups --log-group-name-prefix "$MAIN_LOG_GROUP" --region $REGION | grep -q "$MAIN_LOG_GROUP"; then
    echo -e "${GREEN}✅ 主函数日志组存在${NC}"

    # 查找 EMF 格式的日志
    echo "查找 EMF 指标日志 (最近 5 条):"
    aws logs filter-log-events \
        --log-group-name "$MAIN_LOG_GROUP" \
        --filter-pattern '{
            $.Namespace = "BedrockCostManagement"
        }' \
        --region $REGION \
        --limit 5 \
        --query 'events[0:5].{timestamp:fromtimestamp(@.timestamp/1000),message:@.message}' \
        --output table

    # 检查原始日志
    echo -e "\n原始 EMF 日志示例 (最近 1 条):"
    emf_log=$(aws logs filter-log-events \
        --log-group-name "$MAIN_LOG_GROUP" \
        --filter-pattern '{
            $.Namespace = "BedrockCostManagement"
        }' \
        --region $REGION \
        --limit 1 \
        --query 'events[0].message' \
        --output text 2>/dev/null)

    if [ -n "$emf_log" ] && [ "$emf_log" != "None" ]; then
        echo -e "${GREEN}✅ 找到 EMF 日志${NC}"
        echo "EMF 内容:"
        echo "$emf_log" | jq . 2>/dev/null || echo "$emf_log"

        # 验证 EMF 格式
        echo "EMF 格式验证:"
        if echo "$emf_log" | jq -e 'has("Namespace") and has("Metrics") and has("Dimensions")' >/dev/null 2>&1; then
            echo -e "${GREEN}✅ EMF 格式结构正确${NC}"
        else
            echo -e "${RED}❌ EMF 格式结构错误${NC}"
            echo "EMF 应包含: Namespace, Metrics, Dimensions"
        fi
    else
        echo -e "${RED}❌ 未找到 EMF 日志${NC}"
        echo "在主函数中，将不会有 EMF 指标发出"
    fi
else
    echo -e "${RED}❌ 主函数日志组不存在${NC}"
fi

# 检查成本函数的 EMF 日志
COST_LOG_GROUP="/aws/lambda/bedrock-cost-function"
echo -e "\n成本函数日志组: $COST_LOG_GROUP"

if aws logs describe-log-groups --log-group-name-prefix "$COST_LOG_GROUP" --region $REGION | grep -q "$COST_LOG_GROUP"; then
    echo -e "${GREEN}✅ 成本函数日志组存在${NC}"

    echo "成本函数 EMF 指标日志 (最近 3 条):"
    aws logs filter-log-events \
        --log-group-name "$COST_LOG_GROUP" \
        --filter-pattern '{
            $.Namespace = "BedrockCostManagement"
        }' \
        --region $REGION \
        --limit 3 \
        --query 'events[0:3].{timestamp:fromtimestamp(@.timestamp/1000),message:@.message}' \
        --output table
else
    echo -e "${RED}❌ 成本函数日志组不存在${NC}"
fi
echo ""

# 2. 检查 CloudWatch 命名空间
echo -e "${YELLOW}🔍 步骤 2: 检查 CloudWatch 命名空间${NC}"
echo "查询 CloudWatch Metrics API 中的命名空间..."

# 列出所有可用的命名空间
aws cloudwatch list-metrics \
    --namespace "$METRICS_NAMESPACE" \
    --region $REGION \
    --query 'Metrics[0:5].[MetricName,Dimensions[0].Name]' \
    --output table 2>/dev/null || echo -e "${RED}❌ 命名空间 '$METRICS_NAMESPACE' 中没有找到指标${NC}"

# 检查具体的指标名称
METRICS=("InvocationCount" "InvocationCost" "InputTokens" "OutputTokens" "HighCostInvocation")

echo -e "\n${YELLOW}具体的指标检查:${NC}"
for metric in "${METRICS[@]}"; do
    count=$(aws cloudwatch list-metrics \
        --namespace "$METRICS_NAMESPACE" \
        --metric-name "$metric" \
        --region $REGION \
        --query 'length(Metrics)' \
        --output text 2>/dev/null || echo "0")

    if [ "$count" -gt 0 ]; then
        echo -e "${GREEN}✅ $metric: 找到 $count 个时间序列${NC}"
    else
        echo -e "${RED}❌ $metric: 未找到${NC}"
    fi
done
echo ""

# 3. 检查维度配置
echo -e "${YELLOW}🔍 步骤 3: 检查 CloudWatch 维度配置${NC}"
echo "验证 TenantID 和其他维度的配置..."

# 获取可用的维度
DIMENSIONS=$(aws cloudwatch list-metrics \
    --namespace "$METRICS_NAMESPACE" \
    --region $REGION \
    --query 'Metrics[].Dimensions[].Name' \
    --output json 2>/dev/null | jq -r 'unique | .[]' || echo "")

if [ -n "$DIMENSIONS" ]; then
    echo -e "${GREEN}✅ 找到以下维度:${NC}"
    for dim in $DIMENSIONS; do
        echo "  - $dim"
    done

    # 检查特定租户的维度
    expected_dims=("TenantID" "ApplicationID" "ModelID" "Region")
    for expected_dim in "${expected_dims[@]}"; do
        if echo "$DIMENSIONS" | grep -q "$expected_dim"; then
            echo -e "${GREEN}✅ 维度 '$expected_dim' 存在${NC}"

            # 查询该维度的值
            dim_values=$(aws cloudwatch list-metrics \
                --namespace "$METRICS_NAMESPACE" \
                --dimensions Name="$expected_dim" \
                --region $REGION \
                --query "Metrics[].Dimensions[?Name=='$expected_dim'].Value" \
                --output json 2>/dev/null | jq -r 'flatten | unique | .[0:5]' || echo "[]")

            if [ "$dim_values" != "[]" ] && [ -n "$dim_values" ]; then
                echo "  示例值: $dim_values"
            fi
        else
            echo -e "${RED}❌ 维度 '$expected_dim' 不存在${NC}"
        fi
    done
else
    echo -e "${RED}❌ 未找到任何维度${NC}"
fi

# 检查特定租户的数据
if [ "$TENANT_ID" != "tenant-demo1" ]; then
    echo -e "\n${YELLOW}检查特定租户 '$TENANT_ID' 的指标:${NC}"
    tenant_metrics=$(aws cloudwatch list-metrics \
        --namespace "$METRICS_NAMESPACE" \
        --dimensions Name=TenantID,Value="$TENANT_ID" \
        --region $REGION \
        --query 'length(Metrics)' \
        --output text 2>/dev/null || echo "0")

    if [ "$tenant_metrics" -gt 0 ]; then
        echo -e "${GREEN}✅ 找到 $tenant_metrics 个租户 '$TENANT_ID' 的时间序列${NC}"
    else
        echo -e "${RED}❌ 未找到租户 '$TENANT_ID' 的任何指标${NC}"
    fi
fi
echo ""

# 4. 检查 IAM 日志权限
echo -e "${YELLOW}🔍 步骤 4: 检查 IAM 日志权限${NC}"
echo "验证 Lambda 是否有 CloudWatch Logs 权限..."

# 检查 Main Lambda 权限
ROLE_NAME="BedrockMainLambdaRole"
echo "主函数 IAM 角色: $ROLE_NAME"

if aws iam get-role --role-name $ROLE_NAME --region $REGION > /dev/null 2>&1; then
    echo -e "${GREEN}✅ IAM 角色存在${NC}"

    # 检查 CloudWatch Logs 权限
    aws iam simulate-principal-policy \
        --policy-source-arn "arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}" \
        --action-names 'logs:CreateLogGroup' 'logs:CreateLogStream' 'logs:PutLogEvents' \
        --resource-arns '*' \
        --query 'EvaluationResults[].{Action:EvalActionName,Decision:EvalDecision}' \
        --output table 2> /tmp/logs_permissions.json || echo -e "${RED}❌ 权限模拟失败${NC}"

    if [ -f /tmp/logs_permissions.json ]; then
        if grep -q "allowed" /tmp/logs_permissions.json; then
            echo -e "${GREEN}✅ CloudWatch Logs 权限已配置${NC}"
        else
            echo -e "${RED}❌ CloudWatch Logs 权限不足${NC}"
        fi
    fi
else
    echo -e "${RED}❌ IAM 角色不存在${NC}"
fi

# 5. 检查指标提取延迟问题
echo -e "\n${YELLOW}🔍 步骤 5: 检查指标提取延迟${NC}"
echo "EMF 指标提取延迟通常为 5-10 分钟..."

CURRENT_TIME=$(date +%s)
START_TIME=$(date -d '2 hours ago' +%s)

echo "查询最近 2 小时的 InvocationCost 指标:"
aws cloudwatch get-metric-statistics \
    --namespace "$METRICS_NAMESPACE" \
    --metric-name "InvocationCost" \
    --start-time $(date -d @$START_TIME +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -d @$CURRENT_TIME +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum \
    --region $REGION \
    --query 'Datapoints[0:5].{Time:Timestamp,Value:Sum}' \
    --output table 2>/dev/null || echo -e "${RED}❌ 未找到指标数据${NC}"

# 6. 模拟数据测试
echo -e "\n${YELLOW}🔍 步骤 6: 模拟手动指标推送测试${NC}"
echo "发送测试 EMF 日志到 CloudWatch..."

TEST_LOG_GROUP="/aws/lambda/test-emf-manual"
aws logs create-log-group --log-group-name "$TEST_LOG_GROUP" --region $REGION 2>/dev/null || true

# 创建一个测试 EMF 日志消息
cat > /tmp/test_emf.json << 'EOF'
{
  "_aws": {
    "Timestamp": $(date +%s%3N),
    "CloudWatchMetrics": [
      {
        "Namespace": "TestEMFManual",
        "Dimensions": [["TestDimension"]],
        "Metrics": [
          {
            "Name": "TestMetric",
            "Unit": "Count",
            "Value": 1.0
          }
        ]
      }
    ]
  },
  "TestDimension": "TestValue",
  "TestMetric": 1.0
}
EOF

# 发送测试日志
aws logs put-log-events \
    --log-group-name "$TEST_LOG_GROUP" \
    --log-stream-name "test-stream" \
    --log-events timestamp=$(date +%s%3N),message="$(cat /tmp/test_emf.json)" \
    --region $REGION > /dev/null 2>1 && echo -e "${GREEN}✅ 测试 EMF 日志已发送${NC}" || echo -e "${RED}❌ 发送测试日志失败${NC}"

echo "等待 2 分钟以查看测试指标是否出现..."
echo "请稍后手动检查: aws cloudwatch list-metrics --namespace TestEMFManual --region $REGION"
echo ""

# 7. 验证 CloudWatch Logs Insights 查询
echo -e "${YELLOW}🔍 步骤 7: CloudWatch Logs Insights 查询验证${NC}"
echo "使用 Insights 查询 EMF 指标..."

# 执行 Insights 查询（如果数据量不大）
INSIGHTS_QUERY='fields @timestamp, @message
| filter Namespace like /BedrockCostManagement/
| stats count() by bin(5m)'

echo "查询语句:"
echo "$INSIGHTS_QUERY"
echo ""

# 手动查询
aws logs start-query \
    --log-group-name "$MAIN_LOG_GROUP" \
    --start-time $(date -d '1 hour ago' +%s) \
    --end-time $(date +%s) \
    --query-string 'fields @timestamp, TenantID, ApplicationID, InvocationCost | filter InvocationCost \u003e 0 | stats sum(InvocationCost) as TotalCost by TenantID' \
    --region $REGION \
    --output json > /tmp/query_result.json 2>/dev/null && echo -e "${GREEN}✅ Insights 查询已启动${NC}" || echo -e "${YELLOW}ℹ️  手动启动查询，查询 ID 将显示在输出中${NC}"

if [ -f /tmp/query_result.json ]; then
    QUERY_ID=$(cat /tmp/query_result.json | jq -r '.queryId // empty')
    if [ -n "$QUERY_ID" ]; then
        echo "查询 ID: $QUERY_ID"
        echo "等待查询完成..."

        # 等待查询完成
        for i in {1..10}; do
            sleep 3
            RESULT=$(aws logs get-query-results --query-id "$QUERY_ID" --region $REGION --output json 2>/dev/null)
            STATUS=$(echo "$RESULT" | jq -r '.status // "Running"')

            if [ "$STATUS" = "Complete" ]; then
                echo -e "${GREEN}✅ 查询完成${NC}"
                echo "结果:"
                echo "$RESULT" | jq -r '.results // []' | head -10
                break
            elif [ "$STATUS" = "Failed" ]; then
                echo -e "${RED}❌ 查询失败${NC}"
                break
            fi
        done
    fi
fi
echo ""

# 总结
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}指标不显示问题排查总结${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "常见指标不显示原因:"
echo "1. ❌ Lambda 日志权限不足 (logs:CreateLogGroup/Stream/PutLogEvents)"
echo "2. ❌ EMF 格式错误 (JSON 结构不正确)"
echo "3. ❌ 命名空间或指标名称拼写错误"
echo "4. ❌ 维度配置错误 (维度名称/值不匹配)"
echo "5. ❌ 指标提取延迟 (通常需要 5-10 分钟)"
echo "6. ❌ 数据点太少或时间范围错误"
echo ""
echo -e "${YELLOW}推荐解决方案:${NC}"
echo "1. 检查 Lambda IAM 角色的 CloudWatch Logs 权限"
echo "2. 验证 EMF JSON 格式正确 (包含 _aws, Namespace, Metrics, Dimensions)"
echo "3. 确保命名空间和指标名称拼写正确，区分大小写"
echo "4. 确认维度配置一致，名称和值都正确"
echo "5. 等待 10-15 分钟后再次查询指标"
echo "6. 使用 CloudWatch Logs Insights 验证 EMF 日志是否存在"
echo ""

# 清理临时文件
rm -f /tmp/logs_permissions.json /tmp/test_emf.json /tmp/query_result.json

echo -e "${GREEN}✅ 排查完成！${NC}"
echo "如需进一步帮助，请运行其他排查脚本："
echo "  - ./troubleshoot_bedrock.sh  (Bedrock 调用问题)"
echo "  - ./troubleshoot_budget.sh  (预算更新问题)"
echo "  - ./troubleshoot_apigateway.sh (API Gateway 问题)"