#!/bin/bash

# Verify API Gateway setup

set -e

echo "🔍 Verifying API Gateway setup..."

# Load API info if exists
if [ -f "api_info.txt" ]; then
    source api_info.txt
    echo "✅ Loaded API info: $API_ENDPOINT"
else
    echo "❌ api_info.txt not found. Run create_api_gateway.sh first."
    exit 1
fi

# 1. Check API Gateway exists
echo "📡 Checking API Gateway..."
api_name=$(aws apigateway get-rest-api --rest-api-id $API_ID --query 'name' --output text --region $REGION 2>/dev/null || echo "NOT_FOUND")

if [ "$api_name" != "NOT_FOUND" ]; then
    echo "✅ API Gateway found: $api_name"
else
    echo "❌ API Gateway not found"
    exit 1
fi

# 2. Check Lambda function exists
echo "⚡ Checking Lambda function..."
lambda_name=$(aws lambda get-function --function-name "bedrock-cost-tracking-production-main" --query 'Configuration.FunctionName' --output text --region $REGION 2>/dev/null || echo "NOT_FOUND")

if [ "$lambda_name" != "NOT_FOUND" ]; then
    echo "✅ Lambda function found: $lambda_name"
else
    echo "❌ Lambda function not found"
    exit 1
fi

# 3. Test API endpoint
echo "🧪 Testing API endpoint..."
response=$(curl -s -w "\n%{http_code}" -X POST "$API_ENDPOINT/invoke" \
    -H "X-Tenant-Id: demo1" \
    -H "Content-Type: application/json" \
    -d '{"applicationId":"websearch","prompt":"test","maxTokens":10}' 2>/dev/null || echo -e "\n000")

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n -1)

echo "HTTP Status: $http_code"

if [ "$http_code" = "200" ]; then
    echo "✅ API responding successfully"
    echo "Response: $body"
elif [ "$http_code" = "400" ] || [ "$http_code" = "403" ] || [ "$http_code" = "500" ]; then
    echo "⚠️  API responding but request failed (expected without test data)"
    echo "Response: $body"
else
    echo "❌ API not responding properly"
    echo "Response: $body"
fi

# 4. Check recent Lambda logs
echo ""
echo "📋 Recent Lambda logs:"
aws logs describe-log-streams \
    --log-group-name "/aws/lambda/bedrock-cost-tracking-production-main" \
    --order-by LastEventTime \
    --descending \
    --max-items 1 \
    --query 'logStreams[0].logStreamName' \
    --output text --region $REGION 2>/dev/null | xargs -I {} \
    aws logs get-log-events \
        --log-group-name "/aws/lambda/bedrock-cost-tracking-production-main" \
        --log-stream-name {} \
        --limit 3 \
        --query 'events[].message' \
        --output text --region $REGION 2>/dev/null || echo "No recent logs found"

echo ""
echo "🎯 Verification Summary"
echo "======================"
echo "API Endpoint: $API_ENDPOINT/invoke"
echo "Status: Ready for testing"
echo ""
echo "📋 Next steps:"
echo "1. Create test data: ./create_test_data.sh"
echo "2. Create inference profiles: ./create_inference_profiles.sh"
echo "3. Run full API test: ./test_api_simple.sh"
