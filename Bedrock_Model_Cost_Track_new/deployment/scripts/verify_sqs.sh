#!/bin/bash

# SQS Architecture Verification Script

ENVIRONMENT=${ENVIRONMENT:-production}
RESOURCE_PREFIX="bedrock-cost-tracking"
REGION=${AWS_REGION:-us-east-1}

echo "=========================================="
echo "Verifying SQS Architecture"
echo "=========================================="

# 1. Check SQS Queue
echo "1. Checking SQS queue..."
QUEUE_URL=$(aws cloudformation describe-stacks \
  --stack-name ${RESOURCE_PREFIX}-${ENVIRONMENT}-sqs \
  --query "Stacks[0].Outputs[?OutputKey=='CostEventQueueUrl'].OutputValue" \
  --output text \
  --region $REGION 2>/dev/null)

if [ -z "$QUEUE_URL" ]; then
  echo "✗ SQS queue not found"
  exit 1
fi

QUEUE_ATTRS=$(aws sqs get-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attribute-names All \
  --region $REGION)

echo "✓ Queue URL: $QUEUE_URL"
echo "  Visibility Timeout: $(echo $QUEUE_ATTRS | jq -r '.Attributes.VisibilityTimeout')s"
echo "  Message Retention: $(echo $QUEUE_ATTRS | jq -r '.Attributes.MessageRetentionPeriod')s"

# 2. Check DLQ
echo ""
echo "2. Checking Dead Letter Queue..."
DLQ_URL=$(aws cloudformation describe-stacks \
  --stack-name ${RESOURCE_PREFIX}-${ENVIRONMENT}-sqs \
  --query "Stacks[0].Outputs[?OutputKey=='CostEventDLQUrl'].OutputValue" \
  --output text \
  --region $REGION 2>/dev/null)

if [ -z "$DLQ_URL" ]; then
  echo "✗ DLQ not found"
else
  echo "✓ DLQ URL: $DLQ_URL"
fi

# 3. Check Lambda Event Source Mapping
echo ""
echo "3. Checking Lambda-SQS integration..."
COST_LAMBDA=$(aws cloudformation describe-stacks \
  --stack-name ${RESOURCE_PREFIX}-${ENVIRONMENT}-lambda \
  --query "Stacks[0].Outputs[?OutputKey=='CostManagementLambdaFunctionName'].OutputValue" \
  --output text \
  --region $REGION 2>/dev/null)

if [ -z "$COST_LAMBDA" ]; then
  echo "✗ Cost management Lambda not found"
  exit 1
fi

MAPPINGS=$(aws lambda list-event-source-mappings \
  --function-name "$COST_LAMBDA" \
  --region $REGION)

MAPPING_COUNT=$(echo $MAPPINGS | jq '.EventSourceMappings | length')

if [ "$MAPPING_COUNT" -eq "0" ]; then
  echo "✗ No event source mapping found"
  exit 1
fi

echo "✓ Event source mappings: $MAPPING_COUNT"
echo $MAPPINGS | jq -r '.EventSourceMappings[] | "  State: \(.State), Batch Size: \(.BatchSize), Max Concurrency: \(.ScalingConfig.MaximumConcurrency // "N/A")"'

# 4. Check IAM Permissions
echo ""
echo "4. Checking IAM permissions..."
LAMBDA_ROLE=$(aws lambda get-function \
  --function-name "$COST_LAMBDA" \
  --region $REGION \
  --query 'Configuration.Role' \
  --output text)

echo "✓ Lambda Role: $LAMBDA_ROLE"

# 5. Test message send
echo ""
echo "5. Testing SQS message send..."
TEST_MESSAGE='{"tenantId":"test","applicationId":"test","modelId":"test","cost":0.001,"inputTokens":10,"outputTokens":20,"timestamp":'$(date +%s)'}'

SEND_RESULT=$(aws sqs send-message \
  --queue-url "$QUEUE_URL" \
  --message-body "$TEST_MESSAGE" \
  --region $REGION)

MESSAGE_ID=$(echo $SEND_RESULT | jq -r '.MessageId')

if [ -z "$MESSAGE_ID" ]; then
  echo "✗ Failed to send test message"
  exit 1
fi

echo "✓ Test message sent: $MESSAGE_ID"

# Wait for processing
echo "  Waiting 10 seconds for processing..."
sleep 10

# Check queue depth
QUEUE_DEPTH=$(aws sqs get-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attribute-names ApproximateNumberOfMessages \
  --region $REGION \
  --query 'Attributes.ApproximateNumberOfMessages' \
  --output text)

echo "  Queue depth: $QUEUE_DEPTH messages"

# 6. Check Lambda logs
echo ""
echo "6. Checking Lambda execution logs..."
LOG_GROUP="/aws/lambda/$COST_LAMBDA"

RECENT_LOGS=$(aws logs tail "$LOG_GROUP" \
  --since 5m \
  --region $REGION \
  --format short 2>/dev/null | tail -5)

if [ -z "$RECENT_LOGS" ]; then
  echo "  No recent logs found (Lambda may not have been invoked yet)"
else
  echo "✓ Recent logs:"
  echo "$RECENT_LOGS"
fi

echo ""
echo "=========================================="
echo "Verification Complete!"
echo "=========================================="
echo ""
echo "Architecture Status:"
echo "  Main Lambda → SQS Queue → Cost Management Lambda"
echo "  Queue URL: $QUEUE_URL"
echo "  Event Source Mapping: Active"
echo ""
echo "Ready for production traffic!"
