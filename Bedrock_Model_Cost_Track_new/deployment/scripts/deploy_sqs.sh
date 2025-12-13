#!/bin/bash
set -e

# SQS Architecture Deployment Script
# Deploys high-throughput cost tracking system with SQS queues

ENVIRONMENT=${ENVIRONMENT:-production}
RESOURCE_PREFIX="bedrock-cost-tracking"
REGION=${AWS_REGION:-us-east-1}

echo "=========================================="
echo "Deploying SQS Architecture"
echo "Environment: $ENVIRONMENT"
echo "Region: $REGION"
echo "=========================================="

# 1. Deploy SQS Queues
echo "Step 1: Deploying SQS queues..."
aws cloudformation deploy \
  --template-file ../../infrastructure/cloudformation/07-sqs-queues.yaml \
  --stack-name ${RESOURCE_PREFIX}-${ENVIRONMENT}-sqs \
  --parameter-overrides \
    Environment=$ENVIRONMENT \
    ResourceNamePrefix=$RESOURCE_PREFIX \
  --region $REGION \
  --no-fail-on-empty-changeset

echo "✓ SQS queues deployed"

# 2. Update IAM Roles (add SQS permissions)
echo "Step 2: Updating IAM roles with SQS permissions..."
aws cloudformation deploy \
  --template-file ../../infrastructure/cloudformation/02-iam-roles.yaml \
  --stack-name ${RESOURCE_PREFIX}-${ENVIRONMENT}-iam \
  --parameter-overrides \
    Environment=$ENVIRONMENT \
    ResourceNamePrefix=$RESOURCE_PREFIX \
    TableNamePrefix=$RESOURCE_PREFIX \
  --capabilities CAPABILITY_NAMED_IAM \
  --region $REGION \
  --no-fail-on-empty-changeset

echo "✓ IAM roles updated"

# 3. Package Lambda functions
echo "Step 3: Packaging Lambda functions..."

# Main Lambda
cd ../../src/lambda
zip -r ../../deployment/packages/lambda_main_sqs.zip \
  lambda_function_resource_groups.py \
  redis_cache.py \
  redis/ \
  redis-*.dist-info/ \
  -x "*.pyc" "__pycache__/*"

# Cost Management Lambda
zip -r ../../deployment/packages/lambda_cost_management.zip \
  lambda_function_cost_management.py \
  -x "*.pyc" "__pycache__/*"

cd ../../deployment/scripts

echo "✓ Lambda functions packaged"

# 4. Upload to S3
echo "Step 4: Uploading Lambda packages to S3..."

BUCKET_NAME="${RESOURCE_PREFIX}-${ENVIRONMENT}-lambda-code-$(aws sts get-caller-identity --query Account --output text)"

# Create bucket if not exists
if ! aws s3 ls "s3://${BUCKET_NAME}" 2>/dev/null; then
  aws s3 mb "s3://${BUCKET_NAME}" --region $REGION
  echo "✓ Created S3 bucket: ${BUCKET_NAME}"
fi

aws s3 cp ../packages/lambda_main_sqs.zip s3://${BUCKET_NAME}/
aws s3 cp ../packages/lambda_cost_management.zip s3://${BUCKET_NAME}/

echo "✓ Lambda packages uploaded"

# 5. Deploy Lambda functions with SQS trigger
echo "Step 5: Deploying Lambda functions..."
aws cloudformation deploy \
  --template-file ../../infrastructure/cloudformation/03-lambda-function.yaml \
  --stack-name ${RESOURCE_PREFIX}-${ENVIRONMENT}-lambda \
  --parameter-overrides \
    Environment=$ENVIRONMENT \
    ResourceNamePrefix=$RESOURCE_PREFIX \
    LambdaCodeBucket=$BUCKET_NAME \
    MainLambdaCodeKey=lambda_main_sqs.zip \
    CostManagementLambdaCodeKey=lambda_cost_management.zip \
    VpcId="${VPC_ID:-}" \
    SubnetIds="${SUBNET_IDS:-}" \
    SecurityGroupIds="${SECURITY_GROUP_IDS:-}" \
  --capabilities CAPABILITY_IAM \
  --region $REGION \
  --no-fail-on-empty-changeset

echo "✓ Lambda functions deployed"

# 6. Get deployment info
echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="

QUEUE_URL=$(aws cloudformation describe-stacks \
  --stack-name ${RESOURCE_PREFIX}-${ENVIRONMENT}-sqs \
  --query "Stacks[0].Outputs[?OutputKey=='CostEventQueueUrl'].OutputValue" \
  --output text \
  --region $REGION)

DLQ_URL=$(aws cloudformation describe-stacks \
  --stack-name ${RESOURCE_PREFIX}-${ENVIRONMENT}-sqs \
  --query "Stacks[0].Outputs[?OutputKey=='CostEventDLQUrl'].OutputValue" \
  --output text \
  --region $REGION)

MAIN_LAMBDA=$(aws cloudformation describe-stacks \
  --stack-name ${RESOURCE_PREFIX}-${ENVIRONMENT}-lambda \
  --query "Stacks[0].Outputs[?OutputKey=='MainLambdaFunctionName'].OutputValue" \
  --output text \
  --region $REGION)

COST_LAMBDA=$(aws cloudformation describe-stacks \
  --stack-name ${RESOURCE_PREFIX}-${ENVIRONMENT}-lambda \
  --query "Stacks[0].Outputs[?OutputKey=='CostManagementLambdaFunctionName'].OutputValue" \
  --output text \
  --region $REGION)

echo "Queue URL: $QUEUE_URL"
echo "DLQ URL: $DLQ_URL"
echo "Main Lambda: $MAIN_LAMBDA"
echo "Cost Management Lambda: $COST_LAMBDA"
echo ""
echo "Architecture: Lambda → SQS → Cost Management Lambda → DynamoDB + CloudWatch"
echo ""
echo "Next steps:"
echo "1. Run: ./verify_sqs.sh"
echo "2. Run E2E tests: cd ../../tests/e2e && python3 run_all_tests.py"
