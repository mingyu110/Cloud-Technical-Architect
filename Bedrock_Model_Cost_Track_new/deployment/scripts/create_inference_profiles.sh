#!/bin/bash

# Create Bedrock Inference Profiles with proper tags
# This script creates inference profiles for different tenants and applications

set -e

# Configuration
REGION="us-east-1"
ENVIRONMENT="production"

# Model configurations
declare -A MODELS=(
    ["nova-pro"]="arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-pro-v1:0"
    ["nova-lite"]="arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-lite-v1:0"
    ["claude-sonnet"]="arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0"
)

# Tenant and application configurations
declare -A TENANTS=(
    ["demo1"]="websearch,chatbot"
    ["demo2"]="analytics,reporting"
    ["tenant1"]="app1,app2"
)

echo "🚀 Creating Bedrock Inference Profiles..."

for tenant_id in "${!TENANTS[@]}"; do
    IFS=',' read -ra APPS <<< "${TENANTS[$tenant_id]}"
    
    for app_id in "${APPS[@]}"; do
        for model_type in "${!MODELS[@]}"; do
            profile_name="${tenant_id}-${app_id}-${model_type}"
            model_arn="${MODELS[$model_type]}"
            
            echo "Creating profile: $profile_name"
            
            # Create inference profile
            aws bedrock create-inference-profile \
                --inference-profile-name "$profile_name" \
                --model-source "{\"copyFrom\": \"$model_arn\"}" \
                --tags "key=TenantID,value=$tenant_id" \
                       "key=ApplicationID,value=$app_id" \
                       "key=ModelType,value=$model_type" \
                       "key=Environment,value=$ENVIRONMENT" \
                --region "$REGION" || {
                echo "⚠️  Failed to create $profile_name (may already exist)"
                continue
            }
            
            echo "✅ Created: $profile_name"
            sleep 1  # Rate limiting
        done
    done
done

echo ""
echo "🔍 Verifying created profiles..."

# List all inference profiles with tags
aws bedrock list-inference-profiles --region "$REGION" --query 'inferenceProfileSummaries[].{Name:inferenceProfileName,Status:status}' --output table

echo ""
echo "🏷️  Checking tags on profiles..."

# Get all Bedrock resources with our tags
aws resourcegroupstaggingapi get-resources \
    --resource-type-filters "bedrock" \
    --tag-filters "Key=Environment,Values=$ENVIRONMENT" \
    --region "$REGION" \
    --query 'ResourceTagMappingList[].{ARN:ResourceARN,Tags:Tags}' \
    --output table

echo ""
echo "✅ Inference profiles creation completed!"
echo ""
echo "📋 Next steps:"
echo "1. Test Resource Groups API query:"
echo "   aws resourcegroupstaggingapi get-resources --resource-type-filters bedrock --tag-filters 'Key=TenantID,Values=demo1'"
echo ""
echo "2. Test Lambda function with created profiles"
echo "3. Verify EMF metrics in CloudWatch"
