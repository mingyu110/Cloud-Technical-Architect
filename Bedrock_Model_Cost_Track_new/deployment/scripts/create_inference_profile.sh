#!/bin/bash
"""
Amazon Bedrock 多租户成本追踪 - 创建推理配置脚本

本脚本创建应用推理配置（Application Inference Profile）用于成本分配
每个租户需要独立的推理配置 ARN

前置条件：
- AWS CLI 已配置
- 已启用 Amazon Bedrock
"""

set -e

echo "======================================================"
echo "Amazon Bedrock 应用推理配置创建脚本"
echo "======================================================"
echo ""

# 配置变量
REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
MODEL_ID="${BEDROCK_MODEL:-anthropic.claude-3-haiku-20240307-v1:0}"
TENANT_ID="${TENANT_ID:-tenant-demo1}"
APPLICATION_ID="${APPLICATION_ID:-websearch}"

# 验证 AWS CLI 配置
echo "步骤 1: 验证 AWS CLI 配置"
if ! aws configure list &> /dev/null; then
    echo "❌ AWS CLI 未配置，请先运行 aws configure"
    exit 1
fi
echo "✅ AWS CLI 配置正确"
echo ""

# 验证 Bedrock 模型可用性
echo "步骤 2: 验证 Bedrock 模型可用性"
if ! aws bedrock list-foundation-models \
    --region $REGION \
    --query "modelSummaries[?modelId=='$MODEL_ID'].modelId" \
    --output text | grep -q "$MODEL_ID"; then
    echo "❌ 模型 $MODEL_ID 在区域 $REGION 中不可用"
    echo "可用模型列表:"
    aws bedrock list-foundation-models \
        --region $REGION \
        --query 'modelSummaries[?providerName==`Anthropic`].modelId' \
        --output table
    exit 1
fi
echo "✅ 模型 $MODEL_ID 可用"
echo ""

# 创建推理配置
echo "步骤 3: 创建应用推理配置"
echo "租户 ID: $TENANT_ID"
echo "应用 ID: $APPLICATION_ID"
echo "区域: $REGION"
echo ""

try {
    INFERENCE_PROFILE_ARN=$(aws bedrock create-inference-profile \
        --region $REGION \
        --inference-profile-name "${TENANT_ID}-${APPLICATION_ID}" \
        --model-source $(echo '{"copyFrom": "arn:aws:bedrock:'$REGION'::foundation-model/'$MODEL_ID'"}') \
        --tags "[
            {\"key\": \"TenantID\", \"value\": \"$TENANT_ID\"},
            {\"key\": \"ApplicationID\", \"value\": \"$APPLICATION_ID\"},
            {\"key\": \"Environment\", \"value\": \"production\"},
            {\"key\": \"CostCenter\", \"value\": \"engineering\"}
        ]" \
        --query 'inferenceProfileArn' \
        --output text)

    echo "✅ 推理配置创建成功！"
    echo "ARN: $INFERENCE_PROFILE_ARN"
    echo ""

    # 保存到文件供后续使用
    mkdir -p deployment/outputs
    echo "$INFERENCE_PROFILE_ARN" > deployment/outputs/${TENANT_ID}_inference_profile_arn.txt
    echo "✅ ARN 已保存到 deployment/outputs/${TENANT_ID}_inference_profile_arn.txt"
    echo ""

} catch {
    echo "❌ 创建推理配置失败"
    echo "错误: $_"
    exit 1
}

# 验证配置
echo "步骤 4: 验证推理配置"
sleep 2

PROFILES=$(aws bedrock list-inference-profiles \
    --region $REGION \
    --type-equals APPLICATION \
    --query "inferenceProfileSummaries[?inferenceProfileArn=='$INFERENCE_PROFILE_ARN'].inferenceProfileName" \
    --output text)

if [ -n "$PROFILES" ]; then
    echo "✅ 配置验证成功"
    echo ""

    # 显示标签
    TAGS=$(aws bedrock list-tags-for-resource \
        --resource-arn $INFERENCE_PROFILE_ARN \
        --query 'tags' \
        --output table)

    echo "配置标签:"
    echo "$TAGS"
    echo ""
else
    echo "⚠️  配置创建成功但查询可能需要等待 10-30 秒"
fi

echo "======================================================"
echo "完成！"
echo "======================================================"
echo ""
echo "下一步:"
echo "1. 在 CloudFormation 部署中使用此 ARN"
echo "2. 或将其添加到 tenant 的配置中"
echo ""
