#!/bin/bash
set -e

# Redis回滚脚本 - 恢复到纯DynamoDB模式

REGION="us-east-1"
LAMBDA_FUNCTION_NAME="BedrockCostTrackingMainFunction"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}回滚到纯DynamoDB模式${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

# 确认回滚
read -p "确认回滚到纯DynamoDB模式？(yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "取消回滚"
    exit 0
fi

# 步骤1: 移除Lambda VPC配置
echo -e "${YELLOW}[1/2] 移除Lambda VPC配置...${NC}"
aws lambda update-function-configuration \
    --function-name $LAMBDA_FUNCTION_NAME \
    --vpc-config SubnetIds=[],SecurityGroupIds=[] \
    --region $REGION > /dev/null

aws lambda wait function-updated \
    --function-name $LAMBDA_FUNCTION_NAME \
    --region $REGION

echo -e "  ${GREEN}✓ VPC配置已移除${NC}"

# 步骤2: 移除REDIS_ENDPOINT环境变量
echo -e "${YELLOW}[2/2] 移除Redis环境变量...${NC}"
aws lambda update-function-configuration \
    --function-name $LAMBDA_FUNCTION_NAME \
    --environment Variables="{
        TENANT_CONFIGS_TABLE=bedrock-cost-tracking-production-tenant-configs,
        TENANT_BUDGETS_TABLE=bedrock-cost-tracking-production-tenant-budgets,
        MODEL_PRICING_TABLE=bedrock-cost-tracking-production-model-pricing,
        SESSIONS_TABLE=bedrock-cost-tracking-production-sessions,
        LOG_LEVEL=INFO
    }" \
    --region $REGION > /dev/null

aws lambda wait function-updated \
    --function-name $LAMBDA_FUNCTION_NAME \
    --region $REGION

echo -e "  ${GREEN}✓ 环境变量已更新${NC}"

# 完成
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}回滚完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}系统已恢复到纯DynamoDB模式${NC}"
echo "Lambda将自动降级，直接查询DynamoDB"
echo ""
echo -e "${YELLOW}验证回滚:${NC}"
echo "  aws lambda invoke --function-name $LAMBDA_FUNCTION_NAME \\"
echo "    --payload '{\"headers\":{\"x-tenant-id\":\"demo1\"},\"body\":\"{\\\"applicationId\\\":\\\"chatbot\\\",\\\"prompt\\\":\\\"Hello\\\",\\\"modelId\\\":\\\"us.amazon.nova-micro-v1:0\\\"}\"}' \\"
echo "    --region $REGION response.json"
echo ""
echo -e "${YELLOW}注意:${NC}"
echo "  - Redis集群未删除，如需删除请手动执行"
echo "  - 安全组未删除，如需删除请手动执行"
echo ""
