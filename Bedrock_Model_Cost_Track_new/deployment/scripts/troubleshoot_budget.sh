#!/bin/bash

# Amazon Bedrock 多租户成本追踪系统 - 预算不更新排查脚本
# 功能：诊断 DynamoDB 预算、EventBridge 事件传递、成本计算等问题
# 用法：./troubleshoot_budget.sh [tenant_id] [region]

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

if [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ 无法获取 AWS 账户 ID，请检查 AWS CLI 配置${NC}"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}预算不更新排查脚本${NC}"
echo -e "${BLUE}租户 ID: $TENANT_ID${NC}"
echo -e "${BLUE}区域: $REGION${NC}"
echo -e "${BLUE}账户: $ACCOUNT_ID${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 0. 初始状态检查
echo -e "${YELLOW}🔍 步骤 0: 初始状态检查${NC}"
echo "当前预算状态:"
current_budget=$(aws dynamodb get-item \
    --table-name TenantBudgets \
    --region $REGION \
    --key '{
        "tenantId": {"S": "'$TENANT_ID'"},
        "modelId": {"S": "ALL"}
    }' \
    --projection-expression "balance, totalBudget, alertThreshold, isActive" \
    --output json 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$current_budget" ]; then
    echo -e "${GREEN}✅ 预算记录存在${NC}"
    echo "$current_budget" | jq '.Item'
    CURRENT_BALANCE=$(echo "$current_budget" | jq -r '.Item.balance.N')
    echo "当前余额: \$$CURRENT_BALANCE"
else
    echo -e "${RED}❌ 无法获取预算记录${NC}"
    echo "可能原因：记录不存在或 DynamoDB 表不存在"
fi
echo ""

# 1. 检查 IAM 权限
echo -e "${YELLOW}🔍 步骤 1: 检查 IAM 权限${NC}"
echo "检查 Cost Management Lambda 角色..."

ROLE_NAME="BedrockCostManagementRole"
if aws iam get-role --role-name $ROLE_NAME --region $REGION > /dev/null 2>&1; then
    echo -e "${GREEN}✅ IAM 角色存在: $ROLE_NAME${NC}"

    # 检查 DynamoDB 权限
    echo -e "\n${YELLOW}检查 DynamoDB 权限:${NC}"
    aws iam simulate-principal-policy \
        --policy-source-arn "arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}" \
        --action-names 'dynamodb:UpdateItem' 'dynamodb:GetItem' \
        --resource-arns "arn:aws:dynamodb:${REGION}:${ACCOUNT_ID}:table/TenantBudgets" \
        --query 'EvaluationResults[].{Action:EvalActionName,Decision:EvalDecision}' \
        --output table 2>/dev/null || echo -e "${RED}❌ 权限模拟失败${NC}"

    # 显示附加策略
    echo "附加的策略:"
    aws iam list-attached-role-policies --role-name $ROLE_NAME --query 'AttachedPolicies[].PolicyName' --output table
    aws iam list-role-policies --role-name $ROLE_NAME --query 'PolicyNames' --output table

else
    echo -e "${RED}❌ IAM 角色不存在: $ROLE_NAME${NC}"
fi
echo ""

# 2. 检查 DynamoDB 表结构
echo -e "${YELLOW}🔍 步骤 2: 检查 DynamoDB 表结构${NC}"
echo "验证 TenantBudgets 表结构..."

table_info=$(aws dynamodb describe-table \
    --table-name TenantBudgets \
    --region $REGION \
    --output json 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$table_info" ]; then
    echo -e "${GREEN}✅ TenantBudgets 表存在${NC}"

    # 检查主键结构
    echo "主键结构:"
    echo "$table_info" | jq '.Table.KeySchema[]'

    # 检查属性定义
    echo "属性定义:"
    echo "$table_info" | jq '.Table.AttributeDefinitions[]'

    # 验证预期的主键
    expected_pk='tenantId'
    expected_sk='modelId'

    actual_pk=$(echo "$table_info" | jq -r '.Table.KeySchema[] | select(.KeyType=="HASH") | .AttributeName')
    actual_sk=$(echo "$table_info" | jq -r '.Table.KeySchema[] | select(.KeyType=="RANGE") | .AttributeName')

    if [ "$actual_pk" = "$expected_pk" ] && [ "$actual_sk" = "$expected_sk" ]; then
        echo -e "${GREEN}✅ 主键结构正确: PK=$actual_pk, SK=$actual_sk${NC}"
    else
        echo -e "${RED}❌ 主键结构错误: 期望 PK=$expected_pk, SK=$expected_sk, 实际 PK=$actual_pk, SK=$actual_sk${NC}"
    fi

else
    echo -e "${RED}❌ TenantBudgets 表不存在或无法访问${NC}"
fi
echo ""

# 3. 手动测试 DynamoDB 更新
echo -e "${YELLOW}🔍 步骤 3: 手动测试 DynamoDB 更新${NC}"
echo "执行测试性的预算更新..."

# 获取当前余额作为基准
base_balance=$(aws dynamodb get-item \
    --table-name TenantBudgets \
    --region $REGION \
    --key '{
        "tenantId": {"S": "'$TENANT_ID'"},
        "modelId": {"S": "ALL"}
    }' \
    --projection-expression "balance" \
    --output json | jq -r '.Item.balance.N // "0"')

echo "基准备余额: \$$base_balance"
echo "执行更新: balance = balance - 0.01"

# 执行更新
update_result=$(aws dynamodb update-item \
    --table-name TenantBudgets \
    --region $REGION \
    --key '{
        "tenantId": {"S": "'$TENANT_ID'"},
        "modelId": {"S": "ALL"}
    }' \
    --update-expression "SET balance = balance - :cost, lastUpdated = :timestamp" \
    --expression-attribute-values '{
        ":cost": {"N": "0.01"},
        ":timestamp": {"N": "'$(date +%s)'"}
    }' \
    --return-values ALL_NEW \
    --output json 2>1)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ DynamoDB 更新成功${NC}"
    new_balance=$(echo "$update_result" | jq -r '.Attributes.balance.N')
    echo "新余额: \$$new_balance"

    # 验证更新是否正确
    expected_balance=$(echo "$base_balance - 0.01" | bc -l)
    if (( $(echo "$new_balance == $expected_balance" | bc -l) )); then
        echo -e "${GREEN}✅ 更新计算正确${NC}"
    else
        echo -e "${RED}❌ 更新计算错误: 期望 \$$expected_balance, 实际 \$$new_balance${NC}"
    fi
else
    echo -e "${RED}❌ DynamoDB 更新失败${NC}"
    echo "错误信息: $update_result"
fi
echo ""

# 4. 检查 EventBridge 事件传递
echo -e "${YELLOW}🔍 步骤 4: 检查 EventBridge 事件传递${NC}"
echo "检查 EventBridge Rule 配置..."

# 检查事件总线
EVENT_BUS_NAME="bedrock-cost-tracking-bus"
if aws events describe-event-bus --name "$EVENT_BUS_NAME" --region $REGION > /dev/null 2>&1; then
    echo -e "${GREEN}✅ 事件总线存在: $EVENT_BUS_NAME${NC}"
else
    echo -e "${RED}❌ 事件总线不存在: $EVENT_BUS_NAME${NC}"
fi

# 检查规则
echo -e "\n${YELLOW}检查 EventBridge 规则:${NC}"
aws events list-rules --region $REGION --query 'Rules[?contains(Name, `bedrock-cost`)].[Name,State]' --output table

# 检查 Lambda 函数是否为规则目标
COST_LAMBDA_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:bedrock-cost-function"
echo -e "\n${YELLOW}检查规则目标配置:${NC}"
aws events list-targets-by-rule \
    --rule "bedrock-cost-tracking-rule" \
    --region $REGION \
    --query 'Targets[].[Id,Arn]' \
    --output table 2>/dev/null || echo -e "${RED}❌ 无法获取规则目标${NC}"
echo ""

# 5. 检查 Lambda 函数状态
echo -e "${YELLOW}🔍 步骤 5: 检查 Lambda 函数状态${NC}"

# 检查主函数
echo "主 Lambda 函数 (bedrock-main-function):"
if aws lambda get-function --function-name bedrock-main-function --region $REGION > /tmp/main_function.json 2>/dev/null; then
    MAIN_STATE=$(cat /tmp/main_function.json | jq -r '.Configuration.State')
    MAIN_LAST_MODIFIED=$(cat /tmp/main_function.json | jq -r '.Configuration.LastModified')
    echo -e "${GREEN}✅ 主函数状态: $MAIN_STATE${NC}"
    echo "最后修改: $MAIN_LAST_MODIFIED"
else
    echo -e "${RED}❌ 主函数不存在或无法访问${NC}"
fi

# 检查成本函数
echo -e "\n成本管理 Lambda 函数 (bedrock-cost-function):"
if aws lambda get-function --function-name bedrock-cost-function --region $REGION > /tmp/cost_function.json 2>/dev/null; then
    COST_STATE=$(cat /tmp/cost_function.json | jq -r '.Configuration.State')
    COST_LAST_MODIFIED=$(cat /tmp/cost_function.json | jq -r '.Configuration.LastModified')
    COST_ENV_VARS=$(cat /tmp/cost_function.json | jq -r '.Configuration.Environment.Variables')
    echo -e "${GREEN}✅ 成本函数状态: $COST_STATE${NC}"
    echo "最后修改: $COST_LAST_MODIFIED"
    echo "环境变量:"
    echo "$COST_ENV_VARS" | jq .
else
    echo -e "${RED}❌ 成本函数不存在或无法访问${NC}"
fi
echo ""

# 6. 检查死信队列 (DLQ)
echo -e "${YELLOW}🔍 步骤 6: 检查死信队列 (DLQ)${NC}"
echo "检查是否有失败的事件在 DLQ 中..."

# 获取 DLQ URL（如果存在）
DLQ_NAME="bedrock-cost-tracking-dlq"
DLQ_URL=$(aws sqs get-queue-url --queue-name "$DLQ_NAME" --region $REGION --output text 2>/dev/null || echo "")

if [ -n "$DLQ_URL" ]; then
    echo -e "${GREEN}✅ DLQ 存在: $DLQ_NAME${NC}"

    # 检查消息数量
    DLQ_ATTR=$(aws sqs get-queue-attributes \
        --queue-url "$DLQ_URL" \
        --attribute-names ApproximateNumberOfMessages \
        --region $REGION \
        --output json)

    MESSAGE_COUNT=$(echo "$DLQ_ATTR" | jq -r '.Attributes.ApproximateNumberOfMessages // "0"')
    echo "DLQ 中的消息数量: $MESSAGE_COUNT"

    if [ "$MESSAGE_COUNT" -gt 0 ]; then
        echo -e "${RED}⚠️  DLQ 中有 $MESSAGE_COUNT 条失败消息${NC}"
        echo "建议检查这些消息内容以诊断失败原因"

        # 查看一条消息
        echo "最近的一条消息:"
        messages=$(aws sqs receive-message \
            --queue-url "$DLQ_URL" \
            --max-number-of-messages 1 \
            --region $REGION \
            --output json 2>/dev/null)

        if [ -n "$messages" ]; then
            echo "$messages" | jq -r '.Messages[0].Body' | jq . 2>/dev/null || echo "$messages" | jq -r '.Messages[0].Body'
        fi
    else
        echo -e "${GREEN}✅ DLQ 中没有失败消息${NC}"
    fi
else
    echo -e "${YELLOW}ℹ️  未找到 DLQ: $DLQ_NAME${NC}"
fi
echo ""

# 7. 检查最近的事件处理
echo -e "${YELLOW}🔍 步骤 7: 检查 CloudWatch 日志中的事件处理${NC}"
echo "查看成本函数最近的日志..."

aws logs filter-log-events \
    --log-group-name /aws/lambda/bedrock-cost-function \
    --region $REGION \
    --filter-pattern "budget update" \
    --limit 5 \
    --query 'events[0:5].{timestamp:fromtimestamp(@.timestamp/1000),message:@.message}' \
    --output table 2>/dev/null || echo -e "${YELLOW}ℹ️  未找到相关日志${NC}"

echo -e "\n最近的错误日志:"
aws logs filter-log-events \
    --log-group-name /aws/lambda/bedrock-cost-function \
    --region $REGION \
    --filter-pattern "ERROR" \
    --limit 5 \
    --query 'events[0:5].{timestamp:fromtimestamp(@.timestamp/1000),message:@.message}' \
    --output table 2>/dev/null || echo -e "${YELLOW}ℹ️  未找到错误日志${NC}"
echo ""

# 总结
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}预算更新问题排查总结${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "常见预算不更新原因:"
echo "1. ❌ IAM 权限不足 (无法更新 DynamoDB)"
echo "2. ❌ EventBridge 规则未正确配置"
echo "3. ❌ Lambda 函数出错 (事件处理失败)"
echo "4. ❌ DynamoDB 表结构不匹配"
echo "5. ❌ 事件在 DLQ 中 (处理失败)"
echo "6. ❌ Lambda 环境变量配置错误"
echo ""
echo -e "${YELLOW}推荐解决方案:${NC}"
echo "1. 检查 IAM 角色权限 (dynamodb:UpdateItem)"
echo "2. 验证 EventBridge 规则和目标配置"
echo "3. 查看 Lambda CloudWatch 日志找错误"
echo "4. 确保 DynamoDB 表结构正确"
echo "5. 检查 DLQ 中的失败事件"
echo "6. 验证 Lambda 环境变量"
echo ""

# 清理临时文件
rm -f /tmp/main_function.json /tmp/cost_function.json

echo -e "${GREEN}✅ 排查完成！${NC}"
echo "如需进一步帮助，请运行 ./troubleshoot_bedrock.sh 检查 Bedrock 相关设置"