#!/bin/bash

# Test Prompt Caching functionality
# This script tests the enhanced cost tracking with caching support

set -e

echo "🧪 Testing Prompt Caching Cost Tracking"
echo "======================================="

# Get API endpoint
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "bedrock-tracking-api" \
    --query 'Stacks[0].Outputs[?OutputKey==`APIEndpoint`].OutputValue' \
    --output text)

if [ -z "$API_ENDPOINT" ]; then
    echo "❌ Could not find API endpoint"
    exit 1
fi

echo "📡 API Endpoint: $API_ENDPOINT"

# Test 1: Regular call (no caching)
echo ""
echo "🔄 Test 1: Regular API call (baseline)"
echo "------------------------------------"

RESPONSE1=$(curl -s -X POST "$API_ENDPOINT/invoke" \
  -H "X-Tenant-Id: cache-test" \
  -H "Content-Type: application/json" \
  -d '{
    "applicationId": "cache-demo",
    "prompt": "What is machine learning? Please provide a comprehensive overview.",
    "maxTokens": 500
  }')

echo "Response: $RESPONSE1" | jq '.'

# Extract cost from first call
COST1=$(echo "$RESPONSE1" | jq -r '.usage.cost // 0')
CACHE_READ1=$(echo "$RESPONSE1" | jq -r '.usage.cacheReadTokens // 0')
CACHE_WRITE1=$(echo "$RESPONSE1" | jq -r '.usage.cacheWriteTokens // 0')

echo "💰 First call cost: $COST1"
echo "📖 Cache read tokens: $CACHE_READ1"
echo "✍️  Cache write tokens: $CACHE_WRITE1"

# Test 2: Similar call (should use caching if enabled)
echo ""
echo "🔄 Test 2: Similar call (potential cache hit)"
echo "--------------------------------------------"

sleep 2  # Brief pause

RESPONSE2=$(curl -s -X POST "$API_ENDPOINT/invoke" \
  -H "X-Tenant-Id: cache-test" \
  -H "Content-Type: application/json" \
  -d '{
    "applicationId": "cache-demo",
    "prompt": "What is machine learning? Can you explain the key concepts?",
    "maxTokens": 500
  }')

echo "Response: $RESPONSE2" | jq '.'

# Extract cost from second call
COST2=$(echo "$RESPONSE2" | jq -r '.usage.cost // 0')
CACHE_READ2=$(echo "$RESPONSE2" | jq -r '.usage.cacheReadTokens // 0')
CACHE_WRITE2=$(echo "$RESPONSE2" | jq -r '.usage.cacheWriteTokens // 0')

echo "💰 Second call cost: $COST2"
echo "📖 Cache read tokens: $CACHE_READ2"
echo "✍️  Cache write tokens: $CACHE_WRITE2"

# Test 3: Check CloudWatch metrics
echo ""
echo "📊 Test 3: Checking CloudWatch metrics"
echo "-------------------------------------"

sleep 5  # Wait for metrics to propagate

# Check for cache-related metrics
aws cloudwatch get-metric-statistics \
    --namespace "BedrockCostManagement" \
    --metric-name "CacheReadTokens" \
    --dimensions Name=TenantID,Value=cache-test \
    --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum \
    --output table || echo "⚠️  Cache metrics not yet available"

# Test 4: Check EventBridge events
echo ""
echo "📨 Test 4: Checking EventBridge events"
echo "-------------------------------------"

# Check cost management Lambda logs for cache processing
aws logs filter-log-events \
    --log-group-name "/aws/lambda/bedrock-cost-tracking-production-cost-management" \
    --start-time $(date -d '2 minutes ago' +%s)000 \
    --filter-pattern "cache" \
    --output table || echo "⚠️  No cache-related logs found yet"

# Summary
echo ""
echo "📋 Test Summary"
echo "==============="
echo "First call cost:  $COST1"
echo "Second call cost: $COST2"

if [ "$CACHE_READ2" -gt 0 ]; then
    echo "✅ Cache functionality detected!"
    echo "   - Cache read tokens: $CACHE_READ2"
    echo "   - Cache write tokens: $CACHE_WRITE2"
    
    # Calculate potential savings
    if [ "$COST1" != "0" ] && [ "$COST2" != "0" ]; then
        SAVINGS=$(echo "scale=4; ($COST1 - $COST2) / $COST1 * 100" | bc -l 2>/dev/null || echo "0")
        echo "   - Potential savings: ${SAVINGS}%"
    fi
else
    echo "ℹ️  No cache activity detected in this test"
    echo "   This could be normal if:"
    echo "   - Prompt caching is not enabled for this model"
    echo "   - Prompts were too different to trigger caching"
    echo "   - Cache points were not set in the requests"
fi

echo ""
echo "🎉 Cache functionality test completed!"
echo ""
echo "💡 To enable prompt caching:"
echo "   1. Ensure your model supports caching"
echo "   2. Add cache points to your requests"
echo "   3. Use similar prompt prefixes"
echo "   4. Check model-specific caching documentation"
