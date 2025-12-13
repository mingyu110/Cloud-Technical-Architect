#!/bin/bash

# Quick Lambda function creation for testing

set -e

REGION="us-east-1"
ENVIRONMENT="production"
RESOURCE_PREFIX="bedrock-cost-tracking"

echo "⚡ Creating Lambda functions quickly..."

# 1. Create basic IAM role for Lambda
ROLE_NAME="${RESOURCE_PREFIX}-${ENVIRONMENT}-lambda-role"

echo "Creating IAM role: $ROLE_NAME"

# Create trust policy
cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create role
aws iam create-role \
    --role-name $ROLE_NAME \
    --assume-role-policy-document file://trust-policy.json \
    --region $REGION || echo "Role may already exist"

# Attach basic execution policy
aws iam attach-role-policy \
    --role-name $ROLE_NAME \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
    --region $REGION

# Create inline policy for DynamoDB, Bedrock, etc.
cat > lambda-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:UpdateItem",
        "dynamodb:Query"
      ],
      "Resource": "arn:aws:dynamodb:${REGION}:*:table/bedrock-cost-tracking-*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:GetInferenceProfile",
        "bedrock:ListTagsForResource"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "tag:GetResources"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "events:PutEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam put-role-policy \
    --role-name $ROLE_NAME \
    --policy-name "${RESOURCE_PREFIX}-policy" \
    --policy-document file://lambda-policy.json \
    --region $REGION

echo "✅ IAM role created"

# Wait for role to be ready
sleep 10

# Get role ARN
ROLE_ARN=$(aws iam get-role --role-name $ROLE_NAME --query 'Role.Arn' --output text --region $REGION)

# 2. Create main Lambda function
echo "Creating main Lambda function..."

cd ..
aws lambda create-function \
    --function-name "${RESOURCE_PREFIX}-${ENVIRONMENT}-main" \
    --runtime python3.11 \
    --role $ROLE_ARN \
    --handler lambda_function_resource_groups.lambda_handler \
    --zip-file fileb://main-lambda.zip \
    --timeout 30 \
    --memory-size 512 \
    --environment Variables="{
        ENVIRONMENT=$ENVIRONMENT,
        EVENT_BUS_NAME=default,
        ENABLE_COST_TRACKING=true,
        LOG_LEVEL=INFO,
        TENANT_CONFIGS_TABLE=bedrock-cost-tracking-production-tenant-configs,
        TENANT_BUDGETS_TABLE=bedrock-cost-tracking-production-tenant-budgets,
        MODEL_PRICING_TABLE=bedrock-cost-tracking-production-model-pricing
    }" \
    --region $REGION

echo "✅ Main Lambda function created"

# 3. Create cost management Lambda function
echo "Creating cost management Lambda function..."

aws lambda create-function \
    --function-name "${RESOURCE_PREFIX}-${ENVIRONMENT}-cost-management" \
    --runtime python3.11 \
    --role $ROLE_ARN \
    --handler lambda_function_cost_management.lambda_handler \
    --zip-file fileb://cost-lambda.zip \
    --timeout 60 \
    --memory-size 256 \
    --environment Variables="{
        ENVIRONMENT=$ENVIRONMENT,
        LOG_LEVEL=INFO,
        TENANT_BUDGETS_TABLE=bedrock-cost-tracking-production-tenant-budgets,
        MODEL_PRICING_TABLE=bedrock-cost-tracking-production-model-pricing
    }" \
    --region $REGION

echo "✅ Cost management Lambda function created"

# Cleanup temp files
rm -f trust-policy.json lambda-policy.json

echo ""
echo "🎉 Lambda functions created successfully!"
echo "Main Lambda: ${RESOURCE_PREFIX}-${ENVIRONMENT}-main"
echo "Cost Lambda: ${RESOURCE_PREFIX}-${ENVIRONMENT}-cost-management"
echo "IAM Role: $ROLE_ARN"
