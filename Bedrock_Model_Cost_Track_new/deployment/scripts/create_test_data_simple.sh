#!/bin/bash

# Simple test data creation script

set -e

REGION="us-east-1"
TABLE_PREFIX="bedrock-cost-tracking-production"

echo "📊 Creating simple test data..."

# 1. Create DynamoDB tables first
echo "Creating DynamoDB tables..."

# Model Pricing Table
aws dynamodb create-table \
    --table-name "${TABLE_PREFIX}-model-pricing" \
    --attribute-definitions \
        AttributeName=region,AttributeType=S \
        AttributeName=modelId,AttributeType=S \
    --key-schema \
        AttributeName=region,KeyType=HASH \
        AttributeName=modelId,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST \
    --region $REGION || echo "Table may already exist"

# Tenant Configs Table
aws dynamodb create-table \
    --table-name "${TABLE_PREFIX}-tenant-configs" \
    --attribute-definitions \
        AttributeName=tenantId,AttributeType=S \
    --key-schema \
        AttributeName=tenantId,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region $REGION || echo "Table may already exist"

# Tenant Budgets Table
aws dynamodb create-table \
    --table-name "${TABLE_PREFIX}-tenant-budgets" \
    --attribute-definitions \
        AttributeName=tenantId,AttributeType=S \
        AttributeName=modelId,AttributeType=S \
    --key-schema \
        AttributeName=tenantId,KeyType=HASH \
        AttributeName=modelId,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST \
    --region $REGION || echo "Table may already exist"

echo "Waiting for tables to be active..."
sleep 30

# 2. Add test data
echo "Adding model pricing data..."

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

echo "Adding tenant config..."

aws dynamodb put-item \
    --table-name "${TABLE_PREFIX}-tenant-configs" \
    --item '{
        "tenantId": {"S": "demo1"},
        "defaultModelId": {"S": "amazon.nova-pro-v1:0"},
        "allowedModels": {"L": [{"S": "amazon.nova-pro-v1:0"}]},
        "maxTokens": {"N": "2000"}
    }' \
    --region $REGION

echo "Adding tenant budget..."

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

echo "✅ Test data created successfully!"
echo ""
echo "📋 Created:"
echo "- Model pricing for amazon.nova-pro-v1:0"
echo "- Tenant config for demo1"
echo "- Budget for demo1: $10.00"
