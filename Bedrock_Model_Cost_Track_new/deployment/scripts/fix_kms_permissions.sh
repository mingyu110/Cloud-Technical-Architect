#!/bin/bash

# Fix KMS permissions for Lambda role

set -e

REGION="us-east-1"
ROLE_NAME="bedrock-cost-tracking-production-lambda-role"
KMS_KEY_ID="f2132cbb-8aaa-4943-8bba-a3b9a55e8b77"

echo "🔐 Adding KMS permissions to Lambda role..."

# Create KMS policy
cat > kms-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:GenerateDataKey"
      ],
      "Resource": "arn:aws:kms:${REGION}:*:key/${KMS_KEY_ID}"
    }
  ]
}
EOF

# Add KMS policy to role
aws iam put-role-policy \
    --role-name $ROLE_NAME \
    --policy-name "KMSAccess" \
    --policy-document file://kms-policy.json \
    --region $REGION

echo "✅ KMS permissions added"

# Cleanup
rm -f kms-policy.json

echo "🧪 Testing API again..."
sleep 5

curl -X POST https://tor8uppsc3.execute-api.us-east-1.amazonaws.com/production/invoke \
  -H "X-Tenant-Id: demo1" \
  -H "Content-Type: application/json" \
  -d '{"applicationId":"websearch","prompt":"Hello world","maxTokens":50}'
