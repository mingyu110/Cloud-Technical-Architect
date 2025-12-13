#!/bin/bash
set -e

# Redis + DynamoDB 混合存储部署脚本
# 自动化部署ElastiCache Redis和更新Lambda配置

REGION="us-east-1"
REDIS_CLUSTER_ID="bedrock-cost-tracking-redis"
REDIS_SUBNET_GROUP="bedrock-cost-tracking-redis-subnet"
REDIS_SG_NAME="bedrock-cost-tracking-redis-sg"
LAMBDA_SG_NAME="bedrock-cost-tracking-lambda-sg"
LAMBDA_FUNCTION_NAME="BedrockCostTrackingMainFunction"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Redis + DynamoDB 混合存储部署${NC}"
echo -e "${GREEN}========================================${NC}"

# 检查必需的环境变量
if [ -z "$VPC_ID" ]; then
    echo -e "${RED}错误: 请设置 VPC_ID 环境变量${NC}"
    echo "示例: export VPC_ID=vpc-xxx"
    exit 1
fi

if [ -z "$SUBNET_IDS" ]; then
    echo -e "${RED}错误: 请设置 SUBNET_IDS 环境变量${NC}"
    echo "示例: export SUBNET_IDS=subnet-xxx,subnet-yyy"
    exit 1
fi

echo -e "${YELLOW}配置信息:${NC}"
echo "  Region: $REGION"
echo "  VPC ID: $VPC_ID"
echo "  Subnet IDs: $SUBNET_IDS"
echo ""

# 步骤1: 创建Redis子网组
echo -e "${YELLOW}[1/7] 创建Redis子网组...${NC}"
if aws elasticache describe-cache-subnet-groups \
    --cache-subnet-group-name $REDIS_SUBNET_GROUP \
    --region $REGION &>/dev/null; then
    echo "  子网组已存在，跳过"
else
    IFS=',' read -ra SUBNET_ARRAY <<< "$SUBNET_IDS"
    aws elasticache create-cache-subnet-group \
        --cache-subnet-group-name $REDIS_SUBNET_GROUP \
        --cache-subnet-group-description "Subnet group for Bedrock cost tracking Redis" \
        --subnet-ids ${SUBNET_ARRAY[@]} \
        --region $REGION
    echo -e "  ${GREEN}✓ 子网组创建成功${NC}"
fi

# 步骤2: 创建Redis安全组
echo -e "${YELLOW}[2/7] 创建Redis安全组...${NC}"
REDIS_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$REDIS_SG_NAME" "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[0].GroupId' \
    --output text \
    --region $REGION 2>/dev/null)

if [ "$REDIS_SG_ID" != "None" ] && [ -n "$REDIS_SG_ID" ]; then
    echo "  Redis安全组已存在: $REDIS_SG_ID"
else
    REDIS_SG_ID=$(aws ec2 create-security-group \
        --group-name $REDIS_SG_NAME \
        --description "Security group for Redis cache" \
        --vpc-id $VPC_ID \
        --region $REGION \
        --query 'GroupId' \
        --output text)
    echo -e "  ${GREEN}✓ Redis安全组创建成功: $REDIS_SG_ID${NC}"
fi

# 步骤3: 创建Lambda安全组
echo -e "${YELLOW}[3/7] 创建Lambda安全组...${NC}"
LAMBDA_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$LAMBDA_SG_NAME" "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[0].GroupId' \
    --output text \
    --region $REGION 2>/dev/null)

if [ "$LAMBDA_SG_ID" != "None" ] && [ -n "$LAMBDA_SG_ID" ]; then
    echo "  Lambda安全组已存在: $LAMBDA_SG_ID"
else
    LAMBDA_SG_ID=$(aws ec2 create-security-group \
        --group-name $LAMBDA_SG_NAME \
        --description "Security group for Lambda functions" \
        --vpc-id $VPC_ID \
        --region $REGION \
        --query 'GroupId' \
        --output text)
    echo -e "  ${GREEN}✓ Lambda安全组创建成功: $LAMBDA_SG_ID${NC}"
fi

# 步骤4: 配置安全组规则（Lambda -> Redis）
echo -e "${YELLOW}[4/7] 配置安全组规则...${NC}"
if aws ec2 describe-security-group-rules \
    --filters "Name=group-id,Values=$REDIS_SG_ID" \
    --query "SecurityGroupRules[?FromPort==\`6379\` && ToPort==\`6379\`]" \
    --region $REGION | grep -q "SecurityGroupRuleId"; then
    echo "  安全组规则已存在，跳过"
else
    aws ec2 authorize-security-group-ingress \
        --group-id $REDIS_SG_ID \
        --protocol tcp \
        --port 6379 \
        --source-group $LAMBDA_SG_ID \
        --region $REGION
    echo -e "  ${GREEN}✓ 安全组规则配置成功${NC}"
fi

# 步骤5: 创建Redis集群
echo -e "${YELLOW}[5/7] 创建Redis集群（约5-10分钟）...${NC}"
if aws elasticache describe-cache-clusters \
    --cache-cluster-id $REDIS_CLUSTER_ID \
    --region $REGION &>/dev/null; then
    echo "  Redis集群已存在"
else
    aws elasticache create-cache-cluster \
        --cache-cluster-id $REDIS_CLUSTER_ID \
        --engine redis \
        --cache-node-type cache.t3.small \
        --num-cache-nodes 1 \
        --cache-subnet-group-name $REDIS_SUBNET_GROUP \
        --security-group-ids $REDIS_SG_ID \
        --engine-version 7.0 \
        --region $REGION
    echo "  等待Redis集群创建完成..."
    aws elasticache wait cache-cluster-available \
        --cache-cluster-id $REDIS_CLUSTER_ID \
        --region $REGION
    echo -e "  ${GREEN}✓ Redis集群创建成功${NC}"
fi

# 获取Redis endpoint
REDIS_ENDPOINT=$(aws elasticache describe-cache-clusters \
    --cache-cluster-id $REDIS_CLUSTER_ID \
    --show-cache-node-info \
    --query 'CacheClusters[0].CacheNodes[0].Endpoint.Address' \
    --output text \
    --region $REGION)

echo -e "  ${GREEN}Redis Endpoint: $REDIS_ENDPOINT${NC}"

# 步骤6: 打包Lambda代码
echo -e "${YELLOW}[6/7] 打包Lambda代码...${NC}"
cd "$(dirname "$0")/../../src/lambda"

# 安装redis-py依赖
if [ ! -d "redis" ]; then
    echo "  安装redis-py依赖..."
    pip install redis -t . -q
fi

# 打包
ZIP_FILE="../../deployment/packages/lambda_main_redis.zip"
rm -f $ZIP_FILE
zip -r $ZIP_FILE . -x "*.pyc" -x "__pycache__/*" -q
echo -e "  ${GREEN}✓ Lambda代码打包完成${NC}"

cd - > /dev/null

# 步骤7: 更新Lambda函数
echo -e "${YELLOW}[7/7] 更新Lambda函数...${NC}"

# 更新VPC配置
IFS=',' read -ra SUBNET_ARRAY <<< "$SUBNET_IDS"
SUBNET_JSON=$(printf ',"%s"' "${SUBNET_ARRAY[@]}")
SUBNET_JSON="[${SUBNET_JSON:1}]"

echo "  更新VPC配置..."
aws lambda update-function-configuration \
    --function-name $LAMBDA_FUNCTION_NAME \
    --vpc-config SubnetIds=$SUBNET_JSON,SecurityGroupIds=[$LAMBDA_SG_ID] \
    --region $REGION > /dev/null

aws lambda wait function-updated \
    --function-name $LAMBDA_FUNCTION_NAME \
    --region $REGION

# 更新环境变量
echo "  更新环境变量..."
aws lambda update-function-configuration \
    --function-name $LAMBDA_FUNCTION_NAME \
    --environment Variables="{
        REDIS_ENDPOINT=$REDIS_ENDPOINT,
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

# 更新Lambda代码
echo "  更新Lambda代码..."
aws lambda update-function-code \
    --function-name $LAMBDA_FUNCTION_NAME \
    --zip-file fileb://deployment/packages/lambda_main_redis.zip \
    --region $REGION > /dev/null

aws lambda wait function-updated \
    --function-name $LAMBDA_FUNCTION_NAME \
    --region $REGION

echo -e "  ${GREEN}✓ Lambda函数更新成功${NC}"

# 完成
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}部署完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}部署信息:${NC}"
echo "  Redis Endpoint: $REDIS_ENDPOINT"
echo "  Redis Security Group: $REDIS_SG_ID"
echo "  Lambda Security Group: $LAMBDA_SG_ID"
echo "  Lambda Function: $LAMBDA_FUNCTION_NAME"
echo ""
echo -e "${YELLOW}验证部署:${NC}"
echo "  aws lambda invoke --function-name $LAMBDA_FUNCTION_NAME \\"
echo "    --payload '{\"headers\":{\"x-tenant-id\":\"demo1\"},\"body\":\"{\\\"applicationId\\\":\\\"chatbot\\\",\\\"prompt\\\":\\\"Hello\\\",\\\"modelId\\\":\\\"us.amazon.nova-micro-v1:0\\\"}\"}' \\"
echo "    --region $REGION response.json"
echo ""
echo -e "${YELLOW}查看日志:${NC}"
echo "  aws logs tail /aws/lambda/$LAMBDA_FUNCTION_NAME --follow --region $REGION"
echo ""
echo -e "${YELLOW}监控Redis:${NC}"
echo "  redis-cli -h $REDIS_ENDPOINT"
echo ""
