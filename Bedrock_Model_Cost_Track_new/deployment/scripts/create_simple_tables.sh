#!/bin/bash

# Create simple DynamoDB tables without KMS encryption for testing

set -e

REGION="us-east-1"
TABLE_PREFIX="bedrock-cost-tracking-test"

echo "📊 Creating simple test tables without KMS..."

# Delete existing tables if they exist
aws dynamodb delete-table --table-name "bedrock-cost-tracking-production-model-pricing" --region $REGION 2>/dev/null || true
aws dynamodb delete-table --table-name "bedrock-cost-tracking-production-tenant-configs" --region $REGION 2>/dev/null || true
aws dynamodb delete-table --table-name "bedrock-cost-tracking-production-tenant-budgets" --region $REGION 2>/dev/null || true

echo "Waiting for table deletion..."
sleep 30

# Create new tables without KMS
aws dynamodb create-table \
    --table-name "${TABLE_PREFIX}-model-pricing" \
    --attribute-definitions \
        AttributeName=region,AttributeType=S \
        AttributeName=modelId,AttributeType=S \
    --key-schema \
        AttributeName=region,KeyType=HASH \
        AttributeName=modelId,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST \
    --region $REGION

aws dynamodb create-table \
    --table-name "${TABLE_PREFIX}-tenant-configs" \
    --attribute-definitions \
        AttributeName=tenantId,AttributeType=S \
    --key-schema \
        AttributeName=tenantId,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region $REGION

aws dynamodb create-table \
    --table-name "${TABLE_PREFIX}-tenant-budgets" \
    --attribute-definitions \
        AttributeName=tenantId,AttributeType=S \
        AttributeName=modelId,AttributeType=S \
    --key-schema \
        AttributeName=tenantId,KeyType=HASH \
        AttributeName=modelId,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST \
    --region $REGION

echo "Waiting for tables to be active..."
sleep 30

# Add test data
aws dynamodb put-item \
    --table-name "${TABLE_PREFIX}-model-pricing" \
    --item '{
        "region": {"S": "us-east-1"},
        "modelId": {"S": "amazon.nova-pro-v1:0"},
        "inputCost": {"N": "0.80"},
        "outputCost": {"N": "3.20"},
        "provider": {"S": "Amazon"}
    }' \
    --region $REGION

aws dynamodb put-item \
    --table-name "${TABLE_PREFIX}-tenant-configs" \
    --item '{
        "tenantId": {"S": "demo1"},
        "defaultModelId": {"S": "amazon.nova-pro-v1:0"},
        "allowedModels": {"L": [{"S": "amazon.nova-pro-v1:0"}]},
        "maxTokens": {"N": "2000"}
    }' \
    --region $REGION

aws dynamodb put-item \
    --table-name "${TABLE_PREFIX}-tenant-budgets" \
    --item '{
        "tenantId": {"S": "demo1"},
        "modelId": {"S": "ALL"},
        "balance": {"N": "10.00"},
        "totalBudget": {"N": "10.00"},
        "alertThreshold": {"N": "0.8"},
        "isActive": {"BOOL": true}
    }' \
    --region $REGION

echo "✅ Test tables created successfully!"

# Update Lambda environment variables
aws lambda update-function-configuration \
    --function-name "bedrock-cost-tracking-production-main" \
    --environment Variables="{
        ENVIRONMENT=production,
        EVENT_BUS_NAME=default,
        ENABLE_COST_TRACKING=true,
        LOG_LEVEL=INFO,
        TENANT_CONFIGS_TABLE=${TABLE_PREFIX}-tenant-configs,
        TENANT_BUDGETS_TABLE=${TABLE_PREFIX}-tenant-budgets,
        MODEL_PRICING_TABLE=${TABLE_PREFIX}-model-pricing
    }" \
    --region $REGION

echo "✅ Lambda environment updated"
echo ""
echo "🧪 Testing API..."
sleep 5

curl -X POST https://tor8uppsc3.execute-api.us-east-1.amazonaws.com/production/invoke \
  -H "X-Tenant-Id: demo1" \
  -H "Content-Type: application/json" \
  -d '{"applicationId":"websearch","prompt":"Hello world","maxTokens":50}'
