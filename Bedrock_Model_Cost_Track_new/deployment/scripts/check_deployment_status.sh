#!/bin/bash

# 部署状态检查脚本

ENVIRONMENT=${ENVIRONMENT:-production}
RESOURCE_PREFIX="bedrock-cost-tracking"
REGION=${AWS_REGION:-us-east-1}

echo "=========================================="
echo "检查部署状态"
echo "Environment: $ENVIRONMENT"
echo "Region: $REGION"
echo "=========================================="
echo ""

# 检查CloudFormation栈
check_stack() {
    local stack_name=$1
    local description=$2
    
    if aws cloudformation describe-stacks --stack-name "$stack_name" --region $REGION &>/dev/null; then
        local status=$(aws cloudformation describe-stacks --stack-name "$stack_name" --region $REGION --query 'Stacks[0].StackStatus' --output text)
        echo "✓ $description: $status"
        return 0
    else
        echo "✗ $description: 未部署"
        return 1
    fi
}

# 1. DynamoDB表
echo "1. DynamoDB表"
check_stack "${RESOURCE_PREFIX}-${ENVIRONMENT}-dynamodb" "DynamoDB表"
echo ""

# 2. IAM角色
echo "2. IAM角色"
check_stack "${RESOURCE_PREFIX}-${ENVIRONMENT}-iam" "IAM角色"
echo ""

# 3. SQS队列
echo "3. SQS队列"
check_stack "${RESOURCE_PREFIX}-${ENVIRONMENT}-sqs" "SQS队列"
echo ""

# 4. Lambda函数
echo "4. Lambda函数"
check_stack "${RESOURCE_PREFIX}-${ENVIRONMENT}-lambda" "Lambda函数"
echo ""

# 5. 监控
echo "5. 监控"
check_stack "${RESOURCE_PREFIX}-${ENVIRONMENT}-monitoring" "CloudWatch监控"
echo ""

# 6. API Gateway
echo "6. API Gateway"
check_stack "${RESOURCE_PREFIX}-${ENVIRONMENT}-api" "API Gateway"
echo ""

# 检查Lambda函数代码版本
echo "=========================================="
echo "Lambda函数详情"
echo "=========================================="

MAIN_LAMBDA="${RESOURCE_PREFIX}-${ENVIRONMENT}-bedrock-main"
COST_LAMBDA="${RESOURCE_PREFIX}-${ENVIRONMENT}-cost-management"

if aws lambda get-function --function-name "$MAIN_LAMBDA" --region $REGION &>/dev/null; then
    echo "主Lambda函数:"
    aws lambda get-function --function-name "$MAIN_LAMBDA" --region $REGION --query 'Configuration.{Runtime:Runtime,Memory:MemorySize,Timeout:Timeout,LastModified:LastModified}' --output table
else
    echo "✗ 主Lambda函数未部署"
fi

echo ""

if aws lambda get-function --function-name "$COST_LAMBDA" --region $REGION &>/dev/null; then
    echo "成本管理Lambda函数:"
    aws lambda get-function --function-name "$COST_LAMBDA" --region $REGION --query 'Configuration.{Runtime:Runtime,Memory:MemorySize,Timeout:Timeout,LastModified:LastModified}' --output table
else
    echo "✗ 成本管理Lambda函数未部署"
fi

echo ""
echo "=========================================="
echo "部署建议"
echo "=========================================="
echo ""
echo "如需部署SQS架构，请运行："
echo "  ./deploy_sqs.sh"
echo ""
echo "如需更新Lambda代码，请运行："
echo "  ./update_lambdas.sh"
