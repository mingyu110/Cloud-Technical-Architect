#!/bin/bash

# Create simple inference profile for testing

set -e

REGION="us-east-1"
ENVIRONMENT="production"

echo "🤖 Creating test inference profile..."

# Create inference profile for demo1-websearch-nova-pro
aws bedrock create-inference-profile \
    --inference-profile-name "demo1-websearch-nova-pro" \
    --model-source '{"copyFrom": "arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-pro-v1:0"}' \
    --tags key=TenantID,value=demo1 \
           key=ApplicationID,value=websearch \
           key=ModelType,value=nova \
           key=Environment,value=$ENVIRONMENT \
    --region $REGION || echo "Profile may already exist"

echo "✅ Inference profile created"

# Verify profile exists
echo "🔍 Verifying profile..."
aws bedrock list-inference-profiles --region $REGION --query 'inferenceProfileSummaries[?contains(inferenceProfileName, `demo1`)].{Name:inferenceProfileName,Status:status}' --output table

echo ""
echo "🧪 Testing Resource Groups API..."
aws resourcegroupstaggingapi get-resources \
    --resource-type-filters "bedrock" \
    --tag-filters "Key=TenantID,Values=demo1" \
    --region $REGION \
    --query 'ResourceTagMappingList[].{ARN:ResourceARN,Tags:Tags}' \
    --output table

echo ""
echo "🧪 Testing API again..."
sleep 5

curl -X POST https://tor8uppsc3.execute-api.us-east-1.amazonaws.com/production/invoke \
  -H "X-Tenant-Id: demo1" \
  -H "Content-Type: application/json" \
  -d '{"applicationId":"websearch","prompt":"Hello world","maxTokens":50}'
