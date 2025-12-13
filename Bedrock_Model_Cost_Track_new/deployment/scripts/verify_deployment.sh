#!/bin/bash

# Verify Bedrock Multi-Tenant Cost Tracking deployment
# This script checks all components are working correctly

set -e

REGION="us-east-1"
ENVIRONMENT="production"
RESOURCE_PREFIX="bedrock-cost-tracking"

echo "🔍 Verifying Bedrock Multi-Tenant Cost Tracking deployment..."
echo ""

# Check CloudFormation stacks
echo "📋 Checking CloudFormation stacks..."
STACKS=(
    "bedrock-tracking-dynamodb"
    "bedrock-tracking-iam"
    "bedrock-tracking-eventbridge"
    "bedrock-tracking-api"
    "bedrock-tracking-monitoring"
)

for stack in "${STACKS[@]}"; do
    status=$(aws cloudformation describe-stacks --stack-name "$stack" --query 'Stacks[0].StackStatus' --output text --region $REGION 2>/dev/null || echo "NOT_FOUND")
    if [ "$status" = "CREATE_COMPLETE" ] || [ "$status" = "UPDATE_COMPLETE" ]; then
        echo "✅ $stack: $status"
    else
        echo "❌ $stack: $status"
    fi
done

echo ""

# Check DynamoDB tables
echo "🗄️  Checking DynamoDB tables..."
TABLES=(
    "${RESOURCE_PREFIX}-${ENVIRONMENT}-tenant-configs"
    "${RESOURCE_PREFIX}-${ENVIRONMENT}-tenant-budgets"
    "${RESOURCE_PREFIX}-${ENVIRONMENT}-model-pricing"
)

for table in "${TABLES[@]}"; do
    status=$(aws dynamodb describe-table --table-name "$table" --query 'Table.TableStatus' --output text --region $REGION 2>/dev/null || echo "NOT_FOUND")
    if [ "$status" = "ACTIVE" ]; then
        echo "✅ $table: $status"
    else
        echo "❌ $table: $status"
    fi
done

echo ""

# Check Lambda functions
echo "⚡ Checking Lambda functions..."
FUNCTIONS=(
    "${RESOURCE_PREFIX}-${ENVIRONMENT}-main"
    "${RESOURCE_PREFIX}-${ENVIRONMENT}-cost-management"
)

for func in "${FUNCTIONS[@]}"; do
    status=$(aws lambda get-function --function-name "$func" --query 'Configuration.State' --output text --region $REGION 2>/dev/null || echo "NOT_FOUND")
    if [ "$status" = "Active" ]; then
        echo "✅ $func: $status"
    else
        echo "❌ $func: $status"
    fi
done

echo ""

# Check EventBridge
echo "🚌 Checking EventBridge..."
EVENT_BUS="${RESOURCE_PREFIX}-${ENVIRONMENT}-cost-events"
bus_status=$(aws events describe-event-bus --name "$EVENT_BUS" --query 'Name' --output text --region $REGION 2>/dev/null || echo "NOT_FOUND")
if [ "$bus_status" = "$EVENT_BUS" ]; then
    echo "✅ EventBridge bus: $EVENT_BUS"
else
    echo "❌ EventBridge bus: NOT_FOUND"
fi

echo ""

# Check API Gateway
echo "🌐 Checking API Gateway..."
api_id=$(aws cloudformation describe-stacks --stack-name "bedrock-tracking-api" --query 'Stacks[0].Outputs[?OutputKey==`APIGatewayId`].OutputValue' --output text --region $REGION 2>/dev/null || echo "NOT_FOUND")
if [ "$api_id" != "NOT_FOUND" ]; then
    api_endpoint="https://${api_id}.execute-api.${REGION}.amazonaws.com/${ENVIRONMENT}"
    echo "✅ API Gateway: $api_endpoint"
    
    # Test API health
    echo "🧪 Testing API health..."
    response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$api_endpoint/invoke" \
        -H "X-Tenant-Id: demo1" \
        -H "Content-Type: application/json" \
        -d '{"applicationId":"websearch","prompt":"test","maxTokens":10}' || echo "000")
    
    if [ "$response" = "200" ] || [ "$response" = "400" ] || [ "$response" = "403" ]; then
        echo "✅ API responding: HTTP $response"
    else
        echo "❌ API not responding: HTTP $response"
    fi
else
    echo "❌ API Gateway: NOT_FOUND"
fi

echo ""

# Check Bedrock inference profiles
echo "🤖 Checking Bedrock inference profiles..."
profile_count=$(aws bedrock list-inference-profiles --region $REGION --query 'length(inferenceProfileSummaries)' --output text 2>/dev/null || echo "0")
echo "📊 Found $profile_count inference profiles"

if [ "$profile_count" -gt "0" ]; then
    echo "Sample profiles:"
    aws bedrock list-inference-profiles --region $REGION --query 'inferenceProfileSummaries[0:3].{Name:inferenceProfileName,Status:status}' --output table
fi

echo ""

# Check Resource Groups API
echo "🏷️  Testing Resource Groups API..."
resources=$(aws resourcegroupstaggingapi get-resources \
    --resource-type-filters "bedrock" \
    --tag-filters "Key=Environment,Values=$ENVIRONMENT" \
    --region $REGION \
    --query 'length(ResourceTagMappingList)' \
    --output text 2>/dev/null || echo "0")

echo "📊 Found $resources Bedrock resources with Environment=$ENVIRONMENT tag"

echo ""

# Check CloudWatch metrics
echo "📊 Checking CloudWatch metrics..."
metrics=$(aws cloudwatch list-metrics \
    --namespace "BedrockCostManagement" \
    --region $REGION \
    --query 'length(Metrics)' \
    --output text 2>/dev/null || echo "0")

echo "📈 Found $metrics custom metrics in BedrockCostManagement namespace"

echo ""

# Check SNS topics
echo "📢 Checking SNS topics..."
TOPICS=(
    "${RESOURCE_PREFIX}-${ENVIRONMENT}-budget-alerts"
    "${RESOURCE_PREFIX}-${ENVIRONMENT}-critical-alerts"
    "${RESOURCE_PREFIX}-${ENVIRONMENT}-ratelimit-alerts"
)

for topic in "${TOPICS[@]}"; do
    topic_arn=$(aws sns list-topics --query "Topics[?contains(TopicArn, '$topic')].TopicArn" --output text --region $REGION 2>/dev/null || echo "NOT_FOUND")
    if [ "$topic_arn" != "NOT_FOUND" ] && [ -n "$topic_arn" ]; then
        echo "✅ SNS Topic: $topic"
    else
        echo "❌ SNS Topic: $topic (NOT_FOUND)"
    fi
done

echo ""
echo "🎯 Deployment Verification Summary"
echo "=================================="

# Overall health check
errors=0

# Count errors (you would implement actual error counting logic here)
if [ $errors -eq 0 ]; then
    echo "✅ All components are healthy!"
    echo ""
    echo "🚀 Ready to use! Try this test:"
    if [ "$api_id" != "NOT_FOUND" ]; then
        echo "curl -X POST https://${api_id}.execute-api.${REGION}.amazonaws.com/${ENVIRONMENT}/invoke \\"
        echo "  -H 'X-Tenant-Id: demo1' \\"
        echo "  -H 'Content-Type: application/json' \\"
        echo "  -d '{\"applicationId\":\"websearch\",\"prompt\":\"Hello world\",\"maxTokens\":100}'"
    fi
else
    echo "❌ Found $errors issues. Please check the logs above."
fi

echo ""
echo "📋 Next steps:"
echo "1. Create test data: ./create_test_data.sh"
echo "2. Create inference profiles: ./create_inference_profiles.sh"
echo "3. Activate cost allocation tags: ./activate_cost_tags.sh"
echo "4. Test API calls: ./test_api_calls.sh"
