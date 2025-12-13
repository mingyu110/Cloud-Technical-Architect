#!/bin/bash

# One-click deployment script for Bedrock Multi-Tenant Cost Tracking
# This script deploys all CloudFormation stacks and creates necessary resources

set -e

# Configuration
REGION="us-east-1"
ENVIRONMENT="production"
STACK_PREFIX="bedrock-tracking"
RESOURCE_PREFIX="bedrock-cost-tracking"
TABLE_PREFIX="bedrock-cost-tracking"

# S3 bucket for CloudFormation templates (create if not exists)
TEMPLATE_BUCKET="${STACK_PREFIX}-templates-$(date +%s)"

echo "🚀 Starting Bedrock Multi-Tenant Cost Tracking deployment..."
echo "Region: $REGION"
echo "Environment: $ENVIRONMENT"
echo ""

# Step 1: Create S3 bucket for templates
echo "📦 Creating S3 bucket for CloudFormation templates..."
aws s3 mb s3://$TEMPLATE_BUCKET --region $REGION
aws s3api put-bucket-versioning --bucket $TEMPLATE_BUCKET --versioning-configuration Status=Enabled

# Step 2: Package and upload CloudFormation templates
echo "📤 Uploading CloudFormation templates..."
cd ../cloudformation

for template in *.yaml; do
    echo "Uploading $template..."
    aws s3 cp $template s3://$TEMPLATE_BUCKET/cloudformation/ --region $REGION
done

# Step 3: Package Lambda code
echo "📦 Packaging Lambda code..."
cd ../
zip -r main-lambda.zip src/lambda/lambda_function_resource_groups.py
zip -r cost-lambda.zip src/lambda/lambda_function_cost_management.py

aws s3 cp main-lambda.zip s3://$TEMPLATE_BUCKET/lambda/ --region $REGION
aws s3 cp cost-lambda.zip s3://$TEMPLATE_BUCKET/lambda/ --region $REGION

# Step 4: Deploy CloudFormation stacks in order
echo "🏗️  Deploying CloudFormation stacks..."

# 1. DynamoDB Tables
echo "Creating DynamoDB stack..."
aws cloudformation create-stack \
    --stack-name "${STACK_PREFIX}-dynamodb" \
    --template-url "https://s3.amazonaws.com/$TEMPLATE_BUCKET/cloudformation/01-dynamodb-tables.yaml" \
    --parameters ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
                 ParameterKey=TableNamePrefix,ParameterValue=$TABLE_PREFIX \
    --capabilities CAPABILITY_NAMED_IAM \
    --region $REGION

echo "Waiting for DynamoDB stack to complete..."
aws cloudformation wait stack-create-complete --stack-name "${STACK_PREFIX}-dynamodb" --region $REGION

# 2. IAM Roles
echo "Creating IAM stack..."
aws cloudformation create-stack \
    --stack-name "${STACK_PREFIX}-iam" \
    --template-url "https://s3.amazonaws.com/$TEMPLATE_BUCKET/cloudformation/02-iam-roles.yaml" \
    --parameters ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
                 ParameterKey=ResourceNamePrefix,ParameterValue=$RESOURCE_PREFIX \
                 ParameterKey=TableNamePrefix,ParameterValue=$TABLE_PREFIX \
    --capabilities CAPABILITY_NAMED_IAM \
    --region $REGION

echo "Waiting for IAM stack to complete..."
aws cloudformation wait stack-create-complete --stack-name "${STACK_PREFIX}-iam" --region $REGION

# 3. EventBridge
echo "Creating EventBridge stack..."
aws cloudformation create-stack \
    --stack-name "${STACK_PREFIX}-eventbridge" \
    --template-url "https://s3.amazonaws.com/$TEMPLATE_BUCKET/cloudformation/06-eventbridge.yaml" \
    --parameters ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
                 ParameterKey=ResourceNamePrefix,ParameterValue=$RESOURCE_PREFIX \
                 ParameterKey=TableNamePrefix,ParameterValue=$TABLE_PREFIX \
    --capabilities CAPABILITY_NAMED_IAM \
    --region $REGION

echo "Waiting for EventBridge stack to complete..."
aws cloudformation wait stack-create-complete --stack-name "${STACK_PREFIX}-eventbridge" --region $REGION

# 4. Lambda Functions (manual creation for faster deployment)
echo "Creating Lambda functions..."

# Get IAM role ARN
LAMBDA_ROLE_ARN=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_PREFIX}-iam" \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaExecutionRoleArn`].OutputValue' \
    --output text --region $REGION)

# Get EventBridge bus name
EVENT_BUS_NAME=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_PREFIX}-eventbridge" \
    --query 'Stacks[0].Outputs[?OutputKey==`EventBusName`].OutputValue' \
    --output text --region $REGION)

# Create main Lambda function
echo "Creating main Lambda function..."
aws lambda create-function \
    --function-name "${RESOURCE_PREFIX}-${ENVIRONMENT}-main" \
    --runtime python3.11 \
    --role $LAMBDA_ROLE_ARN \
    --handler lambda_function_resource_groups.lambda_handler \
    --zip-file fileb://main-lambda.zip \
    --timeout 30 \
    --memory-size 512 \
    --environment Variables="{
        ENVIRONMENT=$ENVIRONMENT,
        EVENT_BUS_NAME=$EVENT_BUS_NAME,
        ENABLE_COST_TRACKING=true,
        LOG_LEVEL=INFO
    }" \
    --region $REGION

# Create cost management Lambda function
echo "Creating cost management Lambda function..."
aws lambda create-function \
    --function-name "${RESOURCE_PREFIX}-${ENVIRONMENT}-cost-management" \
    --runtime python3.11 \
    --role $LAMBDA_ROLE_ARN \
    --handler lambda_function_cost_management.lambda_handler \
    --zip-file fileb://cost-lambda.zip \
    --timeout 60 \
    --memory-size 256 \
    --environment Variables="{
        ENVIRONMENT=$ENVIRONMENT,
        LOG_LEVEL=INFO
    }" \
    --region $REGION

# 5. API Gateway (manual creation for better control)
echo "Creating API Gateway..."

# Get Lambda function ARN
MAIN_LAMBDA_ARN=$(aws lambda get-function \
    --function-name "${RESOURCE_PREFIX}-${ENVIRONMENT}-main" \
    --query 'Configuration.FunctionArn' \
    --output text --region $REGION)

# Create API Gateway manually instead of CloudFormation
API_ID=$(aws apigateway create-rest-api \
    --name "${RESOURCE_PREFIX}-${ENVIRONMENT}-api" \
    --description "API Gateway for Bedrock multi-tenant cost tracking" \
    --query 'id' --output text --region $REGION)

# Get root resource ID
ROOT_ID=$(aws apigateway get-resources \
    --rest-api-id $API_ID \
    --query 'items[?path==`/`].id' \
    --output text --region $REGION)

# Create /invoke resource
RESOURCE_ID=$(aws apigateway create-resource \
    --rest-api-id $API_ID \
    --parent-id $ROOT_ID \
    --path-part invoke \
    --query 'id' --output text --region $REGION)

# Create POST method
aws apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method POST \
    --authorization-type NONE \
    --region $REGION

# Create Lambda integration
aws apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method POST \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${MAIN_LAMBDA_ARN}/invocations" \
    --region $REGION

# Add Lambda permission for API Gateway
aws lambda add-permission \
    --function-name "${RESOURCE_PREFIX}-${ENVIRONMENT}-main" \
    --statement-id api-gateway-invoke \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:apigateway:${REGION}::/restapis/${API_ID}/*/POST/invoke" \
    --region $REGION

# Deploy API
aws apigateway create-deployment \
    --rest-api-id $API_ID \
    --stage-name $ENVIRONMENT \
    --region $REGION

echo "✅ API Gateway created: https://${API_ID}.execute-api.${REGION}.amazonaws.com/${ENVIRONMENT}"

# 6. Monitoring
echo "Creating monitoring stack..."
aws cloudformation create-stack \
    --stack-name "${STACK_PREFIX}-monitoring" \
    --template-url "https://s3.amazonaws.com/$TEMPLATE_BUCKET/cloudformation/04-monitoring.yaml" \
    --parameters ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
                 ParameterKey=ResourceNamePrefix,ParameterValue=$RESOURCE_PREFIX \
                 ParameterKey=BudgetThreshold,ParameterValue=1000 \
                 ParameterKey=TokenThresholdPerMinute,ParameterValue=10000 \
                 ParameterKey=CostThresholdPerCall,ParameterValue=0.001 \
    --capabilities CAPABILITY_NAMED_IAM \
    --region $REGION

echo "Waiting for monitoring stack to complete..."
aws cloudformation wait stack-create-complete --stack-name "${STACK_PREFIX}-monitoring" --region $REGION

# Step 5: Create test data
echo "📊 Creating test data..."
./create_test_data.sh

# Step 6: Create inference profiles
echo "🔧 Creating Bedrock inference profiles..."
./create_inference_profiles.sh

# Step 7: Get deployment outputs
echo ""
echo "🎉 Deployment completed successfully!"
echo ""
echo "📋 Deployment Summary:"
echo "====================="

# API Gateway endpoint
API_ENDPOINT="https://${API_ID}.execute-api.${REGION}.amazonaws.com/${ENVIRONMENT}"

echo "API Endpoint: $API_ENDPOINT/invoke"

# Dashboard URL
DASHBOARD_URL=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_PREFIX}-monitoring" \
    --query 'Stacks[0].Outputs[?OutputKey==`DashboardUrl`].OutputValue' \
    --output text --region $REGION)

echo "CloudWatch Dashboard: $DASHBOARD_URL"

# Lambda function names
echo "Main Lambda: ${RESOURCE_PREFIX}-${ENVIRONMENT}-main"
echo "Cost Lambda: ${RESOURCE_PREFIX}-${ENVIRONMENT}-cost-management"

echo ""
echo "🧪 Test the deployment:"
echo "curl -X POST $API_ENDPOINT/invoke \\"
echo "  -H 'X-Tenant-Id: demo1' \\"
echo "  -d '{\"applicationId\":\"websearch\",\"prompt\":\"Hello\",\"maxTokens\":100}'"

echo ""
echo "📊 Monitor logs:"
echo "aws logs tail /aws/lambda/${RESOURCE_PREFIX}-${ENVIRONMENT}-main --follow"

echo ""
echo "⚠️  Remember to:"
echo "1. Activate cost allocation tags in Billing Console (TenantID, ApplicationID, ModelType)"
echo "2. Subscribe to SNS topics for alerts"
echo "3. Configure budget thresholds per tenant"

# Cleanup temp files
rm -f main-lambda.zip cost-lambda.zip

echo ""
echo "✅ All resources deployed successfully!"
