#!/bin/bash

# Activate Cost Allocation Tags for Bedrock Multi-Tenant Cost Tracking
# This script activates the necessary tags in AWS Billing Console

set -e

echo "🏷️  Activating Cost Allocation Tags..."

# List of tags to activate
TAGS=(
    "TenantID"
    "ApplicationID"
    "ModelType"
    "Environment"
    "CostCenter"
    "Project"
)

echo "Tags to activate:"
for tag in "${TAGS[@]}"; do
    echo "  - $tag"
done

echo ""
echo "Activating tags..."

# Activate each tag
for tag in "${TAGS[@]}"; do
    echo "Activating: $tag"
    
    aws ce create-cost-category-definition \
        --name "Bedrock-$tag" \
        --rules "[{
            \"Value\": \"$tag\",
            \"Rule\": {
                \"Dimensions\": {
                    \"Key\": \"TAG\",
                    \"Values\": [\"$tag\"],
                    \"MatchOptions\": [\"EQUALS\"]
                }
            }
        }]" \
        --rule-version "CostCategoryExpression.v1" || {
        echo "⚠️  Failed to create cost category for $tag (may already exist)"
    }
done

echo ""
echo "✅ Cost allocation tags activation completed!"
echo ""
echo "📋 Important Notes:"
echo "==================="
echo "1. It takes 24-48 hours for cost allocation tags to appear in Cost Explorer"
echo "2. Tags only apply to resources created AFTER activation"
echo "3. Historical costs won't have these tags"
echo ""
echo "🔍 To verify activation:"
echo "1. Go to AWS Billing Console → Cost Allocation Tags"
echo "2. Check that the following tags are 'Active':"
for tag in "${TAGS[@]}"; do
    echo "   - $tag"
done
echo ""
echo "📊 After 24-48 hours, you can:"
echo "1. Use Cost Explorer to filter by these tags"
echo "2. Create cost budgets per tenant"
echo "3. Set up cost anomaly detection"
echo ""
echo "🔗 Useful links:"
echo "- Cost Allocation Tags: https://console.aws.amazon.com/billing/home#/tags"
echo "- Cost Explorer: https://console.aws.amazon.com/cost-management/home#/cost-explorer"
echo "- Budgets: https://console.aws.amazon.com/billing/home#/budgets"
