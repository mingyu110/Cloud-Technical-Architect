#!/bin/bash

# Create API Gateway manually for Bedrock Multi-Tenant Cost Tracking

set -e

REGION="us-east-1"
ENVIRONMENT="production"
RESOURCE_PREFIX="bedrock-cost-tracking"

echo "🌐 Creating API Gateway..."

# 1. Get Lambda function ARN
MAIN_LAMBDA_ARN=$(aws lambda get-function \
    --function-name "${RESOURCE_PREFIX}-${ENVIRONMENT}-main" \
    --query 'Configuration.FunctionArn' \
    --output text --region $REGION 2>/dev/null || {
    echo "❌ Lambda function not found. Please deploy Lambda first."
    exit 1
})

echo "✅ Found Lambda: $MAIN_LAMBDA_ARN"

# 2. Create REST API
API_ID=$(aws apigateway create-rest-api \
    --name "${RESOURCE_PREFIX}-${ENVIRONMENT}-api" \
    --description "API Gateway for Bedrock multi-tenant cost tracking" \
    --endpoint-configuration types=REGIONAL \
    --query 'id' --output text --region $REGION)

echo "✅ Created API: $API_ID"

# 3. Get root resource ID
ROOT_ID=$(aws apigateway get-resources \
    --rest-api-id $API_ID \
    --query 'items[?path==`/`].id' \
    --output text --region $REGION)

# 4. Create /invoke resource
RESOURCE_ID=$(aws apigateway create-resource \
    --rest-api-id $API_ID \
    --parent-id $ROOT_ID \
    --path-part invoke \
    --query 'id' --output text --region $REGION)

echo "✅ Created resource: /invoke"

# 5. Create POST method
aws apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method POST \
    --authorization-type NONE \
    --region $REGION

# 6. Create OPTIONS method for CORS
aws apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method OPTIONS \
    --authorization-type NONE \
    --region $REGION

# 7. Create Lambda integration for POST
aws apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method POST \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${MAIN_LAMBDA_ARN}/invocations" \
    --region $REGION

# 8. Create CORS integration for OPTIONS
aws apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method OPTIONS \
    --type MOCK \
    --integration-http-method OPTIONS \
    --request-templates '{"application/json": "{\"statusCode\": 200}"}' \
    --region $REGION

# 9. Create method response for OPTIONS
aws apigateway put-method-response \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method OPTIONS \
    --status-code 200 \
    --response-parameters method.response.header.Access-Control-Allow-Headers=false,method.response.header.Access-Control-Allow-Methods=false,method.response.header.Access-Control-Allow-Origin=false \
    --region $REGION

# 10. Create integration response for OPTIONS
aws apigateway put-integration-response \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method OPTIONS \
    --status-code 200 \
    --response-parameters '{"method.response.header.Access-Control-Allow-Headers": "'"'"'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,X-Tenant-Id'"'"'", "method.response.header.Access-Control-Allow-Methods": "'"'"'POST,OPTIONS'"'"'", "method.response.header.Access-Control-Allow-Origin": "'"'"'*'"'"'"}' \
    --region $REGION

# 11. Add Lambda permission for API Gateway
aws lambda add-permission \
    --function-name "${RESOURCE_PREFIX}-${ENVIRONMENT}-main" \
    --statement-id api-gateway-invoke-$(date +%s) \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:${REGION}:$(aws sts get-caller-identity --query Account --output text):${API_ID}/*/*" \
    --region $REGION

echo "✅ Added Lambda permission"

# 12. Deploy API
aws apigateway create-deployment \
    --rest-api-id $API_ID \
    --stage-name $ENVIRONMENT \
    --stage-description "Production deployment" \
    --description "Initial deployment" \
    --region $REGION

echo "✅ Deployed API to stage: $ENVIRONMENT"

# 13. Set up throttling
aws apigateway update-stage \
    --rest-api-id $API_ID \
    --stage-name $ENVIRONMENT \
    --patch-ops op=replace,path=/throttle/rateLimit,value=100 \
    --patch-ops op=replace,path=/throttle/burstLimit,value=200 \
    --region $REGION

echo "✅ Configured throttling"

# 14. Output results
API_ENDPOINT="https://${API_ID}.execute-api.${REGION}.amazonaws.com/${ENVIRONMENT}"

echo ""
echo "🎉 API Gateway created successfully!"
echo "=================================="
echo "API ID: $API_ID"
echo "Endpoint: $API_ENDPOINT/invoke"
echo "Region: $REGION"
echo "Stage: $ENVIRONMENT"
echo ""
echo "🧪 Test command:"
echo "curl -X POST $API_ENDPOINT/invoke \\"
echo "  -H 'X-Tenant-Id: demo1' \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"applicationId\":\"websearch\",\"prompt\":\"Hello\",\"maxTokens\":100}'"
echo ""

# Save API info for other scripts
cat > api_info.txt << EOF
API_ID=$API_ID
API_ENDPOINT=$API_ENDPOINT
REGION=$REGION
ENVIRONMENT=$ENVIRONMENT
EOF

echo "📝 API info saved to api_info.txt"
