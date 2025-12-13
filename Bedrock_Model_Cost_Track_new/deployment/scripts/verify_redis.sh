#!/bin/bash
set -e

# Redis部署验证脚本

REGION="us-east-1"
REDIS_CLUSTER_ID="bedrock-cost-tracking-redis"
LAMBDA_FUNCTION_NAME="BedrockCostTrackingMainFunction"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Redis部署验证${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 检查1: Redis集群状态
echo -e "${YELLOW}[1/5] 检查Redis集群状态...${NC}"
REDIS_STATUS=$(aws elasticache describe-cache-clusters \
    --cache-cluster-id $REDIS_CLUSTER_ID \
    --query 'CacheClusters[0].CacheClusterStatus' \
    --output text \
    --region $REGION 2>/dev/null || echo "NOT_FOUND")

if [ "$REDIS_STATUS" == "available" ]; then
    echo -e "  ${GREEN}✓ Redis集群运行正常${NC}"
    
    REDIS_ENDPOINT=$(aws elasticache describe-cache-clusters \
        --cache-cluster-id $REDIS_CLUSTER_ID \
        --show-cache-node-info \
        --query 'CacheClusters[0].CacheNodes[0].Endpoint.Address' \
        --output text \
        --region $REGION)
    echo "    Endpoint: $REDIS_ENDPOINT"
else
    echo -e "  ${RED}✗ Redis集群状态异常: $REDIS_STATUS${NC}"
    exit 1
fi

# 检查2: Lambda VPC配置
echo -e "${YELLOW}[2/5] 检查Lambda VPC配置...${NC}"
VPC_CONFIG=$(aws lambda get-function-configuration \
    --function-name $LAMBDA_FUNCTION_NAME \
    --query 'VpcConfig.VpcId' \
    --output text \
    --region $REGION 2>/dev/null || echo "NONE")

if [ "$VPC_CONFIG" != "None" ] && [ "$VPC_CONFIG" != "NONE" ]; then
    echo -e "  ${GREEN}✓ Lambda已配置VPC${NC}"
    echo "    VPC ID: $VPC_CONFIG"
else
    echo -e "  ${RED}✗ Lambda未配置VPC${NC}"
    exit 1
fi

# 检查3: Redis环境变量
echo -e "${YELLOW}[3/5] 检查Redis环境变量...${NC}"
REDIS_ENV=$(aws lambda get-function-configuration \
    --function-name $LAMBDA_FUNCTION_NAME \
    --query 'Environment.Variables.REDIS_ENDPOINT' \
    --output text \
    --region $REGION 2>/dev/null || echo "NONE")

if [ "$REDIS_ENV" != "None" ] && [ "$REDIS_ENV" != "NONE" ]; then
    echo -e "  ${GREEN}✓ REDIS_ENDPOINT已配置${NC}"
    echo "    Value: $REDIS_ENV"
else
    echo -e "  ${RED}✗ REDIS_ENDPOINT未配置${NC}"
    exit 1
fi

# 检查4: Redis连接测试
echo -e "${YELLOW}[4/5] 测试Redis连接...${NC}"
if command -v redis-cli &> /dev/null; then
    if redis-cli -h $REDIS_ENDPOINT PING &> /dev/null; then
        echo -e "  ${GREEN}✓ Redis连接成功${NC}"
    else
        echo -e "  ${YELLOW}⚠ Redis连接失败（可能是网络限制）${NC}"
    fi
else
    echo -e "  ${YELLOW}⚠ redis-cli未安装，跳过连接测试${NC}"
fi

# 检查5: Lambda函数测试
echo -e "${YELLOW}[5/5] 测试Lambda函数...${NC}"
RESPONSE_FILE="/tmp/lambda_response_$$.json"

aws lambda invoke \
    --function-name $LAMBDA_FUNCTION_NAME \
    --payload '{"headers":{"x-tenant-id":"demo1"},"body":"{\"applicationId\":\"chatbot\",\"prompt\":\"Hello Redis test\",\"modelId\":\"us.amazon.nova-micro-v1:0\"}"}' \
    --region $REGION \
    $RESPONSE_FILE > /dev/null 2>&1

if [ $? -eq 0 ]; then
    STATUS_CODE=$(cat $RESPONSE_FILE | jq -r '.statusCode' 2>/dev/null || echo "ERROR")
    if [ "$STATUS_CODE" == "200" ]; then
        echo -e "  ${GREEN}✓ Lambda函数执行成功${NC}"
        
        # 检查日志中的Redis缓存信息
        echo ""
        echo -e "${YELLOW}查看最近的Lambda日志（Redis缓存信息）:${NC}"
        aws logs tail /aws/lambda/$LAMBDA_FUNCTION_NAME \
            --since 1m \
            --filter-pattern "Redis" \
            --region $REGION 2>/dev/null | head -20 || echo "  无Redis相关日志"
    else
        echo -e "  ${RED}✗ Lambda函数返回错误: $STATUS_CODE${NC}"
        cat $RESPONSE_FILE
    fi
else
    echo -e "  ${RED}✗ Lambda函数调用失败${NC}"
fi

rm -f $RESPONSE_FILE

# 总结
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}验证完成${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}监控命令:${NC}"
echo "  # 查看Redis统计"
echo "  redis-cli -h $REDIS_ENDPOINT INFO stats"
echo ""
echo "  # 查看缓存键"
echo "  redis-cli -h $REDIS_ENDPOINT KEYS \"*\""
echo ""
echo "  # 查看Lambda日志"
echo "  aws logs tail /aws/lambda/$LAMBDA_FUNCTION_NAME --follow --region $REGION"
echo ""
echo "  # 查看Redis缓存命中"
echo "  aws logs filter-log-events \\"
echo "    --log-group-name /aws/lambda/$LAMBDA_FUNCTION_NAME \\"
echo "    --filter-pattern \"Redis cache hit\" \\"
echo "    --region $REGION"
echo ""
