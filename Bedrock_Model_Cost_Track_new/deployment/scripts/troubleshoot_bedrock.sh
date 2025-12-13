#!/bin/bash

# Amazon Bedrock 多租户成本追踪系统 - Bedrock 调用失败排查脚本
# 功能：诊断 Bedrock 调用相关的权限、模型可用性、ARN等问题
# 用法：./troubleshoot_bedrock.sh [tenant_id] [region]

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
echo -e "${BLUE}Bedrock 调用失败排查脚本${NC}"
echo -e "${BLUE}租户 ID: $TENANT_ID${NC}"
echo -e "${BLUE}区域: $REGION${NC}"
echo -e "${BLUE}账户: $ACCOUNT_ID${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 1. 检查 IAM 权限
echo -e "${YELLOW}🔍 步骤 1: 检查 Lambda IAM 权限${NC}"
echo "检查 Main Lambda 函数策略..."
MAIN_LAMBDA_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:bedrock-main-function"

if aws lambda get-policy --function-name bedrock-main-function --region $REGION > /tmp/lambda_policy.json 2>/dev/null; then
    echo -e "${GREEN}✅ Lambda 策略已配置${NC}"
    echo "策略摘要:"
    cat /tmp/lambda_policy.json | jq -r '.Policy' | jq '.Statement[] | {Effect: .Effect, Action: .Action, Resource: .Resource}' 2>/dev/null || echo "无法解析策略"
else
    echo -e "${RED}❌ 无法获取 Lambda 策略${NC}"
    echo "可能问题: Lambda 函数不存在或权限不足"
fi
echo ""

# 检查 IAM 角色权限
echo "检查 IAM 角色权限..."
ROLE_NAME="BedrockMainLambdaRole"
if aws iam get-role --role-name $ROLE_NAME --region $REGION > /dev/null 2>&1; then
    echo -e "${GREEN}✅ IAM 角色存在: $ROLE_NAME${NC}"

    # 列出所有附加的策略
    echo "附加的策略:"
    aws iam list-attached-role-policies --role-name $ROLE_NAME --query 'AttachedPolicies[].PolicyName' --output table
    aws iam list-role-policies --role-name $ROLE_NAME --query 'PolicyNames' --output table

    # 检查关键权限
    echo -e "\n${YELLOW}检查关键权限:${NC}"
    aws iam simulate-principal-policy \
        --policy-source-arn "arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}" \
        --action-names 'bedrock:InvokeModel' \
        --resource-arns '*' \
        --query 'EvaluationResults[0].EvalDecision' \
        --output text 2>/dev/null | grep -q "allowed" && echo -e "${GREEN}✅ bedrock:InvokeModel 权限: ALLOWED${NC}" || echo -e "${RED}❌ bedrock:InvokeModel 权限: DENIED${NC}"

else
    echo -e "${RED}❌ IAM 角色不存在: $ROLE_NAME${NC}"
fi
echo ""

# 2. 检查 Bedrock 模型可用性
echo -e "${YELLOW}🔍 步骤 2: 检查 Bedrock 模型可用性${NC}"
echo "检查区域中可用的基础模型..."

# 获取指定模型信息
MODEL_ID="anthropic.claude-3-haiku-20240307-v1:0"
if aws bedrock list-foundation-models \
    --region $REGION \
    --query "modelSummaries[?modelId=='$MODEL_ID']" \
    --output json > /tmp/model_check.json 2>/dev/null; then

    if [ -s /tmp/model_check.json ] && [ "$(cat /tmp/model_check.json | jq length)" -gt 0 ]; then
        echo -e "${GREEN}✅ 模型 '$MODEL_ID' 在 $REGION 区域可用${NC}"
        cat /tmp/model_check.json | jq '.[0] | {modelId: .modelId, providerName: .providerName, modelArn: .modelArn, status: .status}'
    else
        echo -e "${RED}❌ 模型 '$MODEL_ID' 在 $REGION 区域不可用${NC}"
        echo "请确保："
        echo "1. 在 Bedrock Console 中启用该模型"
        echo "2. 模型 ID 拼写正确"
    fi
else
    echo -e "${RED}❌ 无法查询 Bedrock 模型列表${NC}"
    echo "可能原因："
    echo "1. Bedrock 服务在当前区域未激活"
    echo "2. 没有足够的权限 (bedrock:ListFoundationModels)"
fi

# 显示所有可用的 Anthropic 模型
echo -e "\n所有可用的 Anthropic 模型:"
aws bedrock list-foundation-models \
    --region $REGION \
    --query 'modelSummaries[?providerName==`Anthropic`].[modelId,status]' \
    --output table 2>/dev/null || echo -e "${RED}❌ 无法获取模型列表${NC}"
echo ""

# 3. 检查应用推理配置 ARN
echo -e "${YELLOW}🔍 步骤 3: 检查应用推理配置 ARN${NC}"
echo "查询租户相关的推理配置..."

aws bedrock list-inference-profiles \
    --region $REGION \
    --query "inferenceProfileSummaries[?contains(inferenceProfileName, '$TENANT_ID')]" \
    --output json > /tmp/inference_profiles.json 2>/dev/null

if [ -s /tmp/inference_profiles.json ]; then
    PROFILES_COUNT=$(cat /tmp/inference_profiles.json | jq length)
    if [ "$PROFILES_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✅ 找到 $PROFILES_COUNT 个推理配置${NC}"
        cat /tmp/inference_profiles.json | jq '.[] | {name: .inferenceProfileName, arn: .inferenceProfileArn, type: .type}'

        # 验证 ARN 格式
        echo -e "\n${YELLOW}验证 ARN 格式:${NC}"
        cat /tmp/inference_profiles.json | jq -r '.[0].inferenceProfileArn' | while read arn; do
            if [[ "$arn" =~ ^arn:aws:bedrock:[^:]+:[0-9]+:inference-profile/[a-zA-Z0-9-]+$ ]]; then
                echo -e "${GREEN}✅ ARN 格式有效: $arn${NC}"
            else
                echo -e "${RED}❌ ARN 格式无效: $arn${NC}"
            fi
        done
    else
        echo -e "${RED}❌ 未找到租户 '$TENANT_ID' 的推理配置${NC}"
        echo "需要创建推理配置，例如："
        echo "aws bedrock create-inference-profile \\"
        echo "  --inference-profile-name \"${TENANT_ID}-websearch\" \\"
        echo "  --model-source '{\"copyFrom\": \"arn:aws:bedrock:${REGION}::foundation-model/anthropic.claude-3-haiku-20240307-v1:0\"}' \\"
        echo "  --tags '[{\"key\": \"TenantID\", \"value\": \"${TENANT_ID}\"}]'"
    fi
else
    echo -e "${RED}❌ 无法获取推理配置列表${NC}"
fi
echo ""

# 4. 检查 CloudWatch Logs
echo -e "${YELLOW}🔍 步骤 4: 检查 CloudWatch 日志${NC}"
LOG_GROUP="/aws/lambda/bedrock-main-function"

if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" --region $REGION | grep -q "$LOG_GROUP"; then
    echo -e "${GREEN}✅ 日志组存在: $LOG_GROUP${NC}"

    # 查找最近的错误日志
    echo "最近的错误日志:"
    aws logs filter-log-events \
        --log-group-name "$LOG_GROUP" \
        --filter-pattern "ERROR" \
        --region $REGION \
        --limit 3 \
        --query 'events[0:3].{timestamp:fromtimestamp(@.timestamp/1000),message:@.message}' \
        --output table 2>/dev/null || echo "未发现错误日志"

    echo -e "\n最近的 Bedrock 调用错误:"
    aws logs filter-log-events \
        --log-group-name "$LOG_GROUP" \
        --filter-pattern "bedrock.*error" \
        --region $REGION \
        --limit 3 \
        --query 'events[0:3].{timestamp:fromtimestamp(@.timestamp/1000),message:@.message}' \
        --output table 2>/dev/null || echo "未发现相关错误"
else
    echo -e "${RED}❌ 日志组不存在: $LOG_GROUP${NC}"
    echo "说明 Lambda 函数从未被调用或未成功启动"
fi
echo ""

# 5. 快速测试
echo -e "${YELLOW}🔍 步骤 5: 快速连通性测试${NC}"
echo "测试 AWS 服务连通性..."

# 测试 STS
if aws sts get-caller-identity >/dev/null 2>&1; then
    echo -e "${GREEN}✅ AWS STS 连通性: OK${NC}"
else
    echo -e "${RED}❌ AWS STS 连通性: FAILED${NC}"
fi

# 测试 Bedrock
if aws bedrock list-foundation-models --region $REGION >/dev/null 2>&1; then
    echo -e "${GREEN}✅ AWS Bedrock 连通性: OK${NC}"
else
    echo -e "${RED}❌ AWS Bedrock 连通性: FAILED${NC}"
fi

# 测试 DynamoDB
if aws dynamodb list-tables --region $REGION >/dev/null 2>&1; then
    echo -e "${GREEN}✅ AWS DynamoDB 连通性: OK${NC}"
else
    echo -e "${RED}❌ AWS DynamoDB 连通性: FAILED${NC}"
fi
echo ""

# 总结
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}排查总结${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "常见 Bedrock 调用失败原因:"
echo "1. ❌ 403 Forbidden - IAM 权限不足"
echo "2. ❌ Model not available - 模型未在区域启用"
echo "3. ❌ Invalid ARN - 推理配置 ARN 格式错误"
echo "4. ❌ Endpoint not found - Bedrock 服务不可用"
echo "5. ❌ Throttling - 请求限流"
echo ""
echo -e "${YELLOW}推荐解决方案:${NC}"
echo "1. 在 Bedrock Console 启用所需模型"
echo "2. 检查 IAM 策略包含 bedrock:InvokeModel"
echo "3. 验证推理配置 ARN 格式正确"
echo "4. 确认区域支持 Bedrock 服务"
echo "5. 检查 Lambda 超时设置（建议 30 秒）"
echo ""

# 清理临时文件
rm -f /tmp/lambda_policy.json /tmp/model_check.json /tmp/inference_profiles.json

echo -e "${GREEN}✅ 排查完成！${NC}"
echo "如需进一步帮助，请提供以上输出的详细信息"