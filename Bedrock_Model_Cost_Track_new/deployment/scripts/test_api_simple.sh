#!/bin/bash

# Simple API test script for Bedrock Multi-Tenant Cost Tracking

set -e

REGION="us-east-1"
ENVIRONMENT="production"
RESOURCE_PREFIX="bedrock-cost-tracking"

echo "🧪 Testing Bedrock Multi-Tenant API..."

# Get API Gateway ID (assuming it was created manually)
API_ID=$(aws apigateway get-rest-apis \
    --query "items[?name=='${RESOURCE_PREFIX}-${ENVIRONMENT}-api'].id" \
    --output text --region $REGION)

if [ -z "$API_ID" ] || [ "$API_ID" = "None" ]; then
    echo "❌ API Gateway not found. Please run deploy_all.sh first."
    exit 1
fi

API_ENDPOINT="https://${API_ID}.execute-api.${REGION}.amazonaws.com/${ENVIRONMENT}"

echo "📡 API Endpoint: $API_ENDPOINT/invoke"
echo ""

# Test 1: Basic API call
echo "🔍 Test 1: Basic API call..."
response=$(curl -s -w "\n%{http_code}" -X POST "$API_ENDPOINT/invoke" \
    -H "X-Tenant-Id: demo1" \
    -H "Content-Type: application/json" \
    -d '{
        "applicationId": "websearch",
        "prompt": "Hello world",
        "maxTokens": 50
    }')

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n -1)

echo "HTTP Status: $http_code"
echo "Response: $body"

if [ "$http_code" = "200" ]; then
    echo "✅ Test 1 passed"
elif [ "$http_code" = "400" ] || [ "$http_code" = "403" ]; then
    echo "⚠️  Test 1: API responding but request failed (expected for missing data)"
else
    echo "❌ Test 1 failed"
fi

echo ""

# Test 2: Missing tenant ID
echo "🔍 Test 2: Missing tenant ID (should fail)..."
response=$(curl -s -w "\n%{http_code}" -X POST "$API_ENDPOINT/invoke" \
    -H "Content-Type: application/json" \
    -d '{
        "applicationId": "websearch",
        "prompt": "Hello world",
        "maxTokens": 50
    }')

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n -1)

echo "HTTP Status: $http_code"
echo "Response: $body"

if [ "$http_code" = "400" ]; then
    echo "✅ Test 2 passed (correctly rejected missing tenant ID)"
else
    echo "❌ Test 2 failed"
fi

echo ""

# Test 3: Check Lambda logs
echo "🔍 Test 3: Checking Lambda logs..."
MAIN_LAMBDA_NAME="${RESOURCE_PREFIX}-${ENVIRONMENT}-main"

echo "Recent logs from $MAIN_LAMBDA_NAME:"
aws logs describe-log-streams \
    --log-group-name "/aws/lambda/$MAIN_LAMBDA_NAME" \
    --order-by LastEventTime \
    --descending \
    --max-items 1 \
    --query 'logStreams[0].logStreamName' \
    --output text --region $REGION | xargs -I {} \
    aws logs get-log-events \
        --log-group-name "/aws/lambda/$MAIN_LAMBDA_NAME" \
        --log-stream-name {} \
        --limit 5 \
        --query 'events[].message' \
        --output text --region $REGION

echo ""
echo "🎯 Test Summary"
echo "==============="
echo "API Endpoint: $API_ENDPOINT/invoke"
echo "Main Lambda: $MAIN_LAMBDA_NAME"
echo ""
echo "📋 Next steps:"
echo "1. Create test data: ./create_test_data.sh"
echo "2. Create inference profiles: ./create_inference_profiles.sh"
echo "3. Run full test suite: ./test_api_calls.sh"
