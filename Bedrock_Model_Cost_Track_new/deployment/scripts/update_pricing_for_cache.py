#!/usr/bin/env python3
"""
Update model pricing table to include cache discount information
"""

import boto3
from decimal import Decimal

def update_model_pricing_with_cache():
    """Add cache discount to existing model pricing entries"""
    
    dynamodb = boto3.resource('dynamodb')
    table = dynamodb.Table('bedrock-cost-tracking-production-model-pricing')
    
    # Cache discount rates (typically 50% for most models)
    cache_discounts = {
        'amazon.nova-pro-v1:0': Decimal('0.5'),
        'amazon.nova-lite-v1:0': Decimal('0.5'),
        'amazon.nova-micro-v1:0': Decimal('0.5'),
        'anthropic.claude-3-sonnet-20240229-v1:0': Decimal('0.5'),
        'anthropic.claude-3-haiku-20240307-v1:0': Decimal('0.5'),
        'anthropic.claude-3-opus-20240229-v1:0': Decimal('0.5'),
        'anthropic.claude-3-5-sonnet-20241022-v2:0': Decimal('0.5'),
        'anthropic.claude-3-5-haiku-20241022-v1:0': Decimal('0.5'),
    }
    
    # Scan all existing entries
    response = table.scan()
    items = response['Items']
    
    # Continue scanning if there are more items
    while 'LastEvaluatedKey' in response:
        response = table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
        items.extend(response['Items'])
    
    print(f"Found {len(items)} pricing entries to update")
    
    # Update each entry with cache discount
    for item in items:
        region = item['region']
        model_id = item['modelId']
        
        # Get cache discount for this model (default to 50%)
        cache_discount = cache_discounts.get(model_id, Decimal('0.5'))
        
        try:
            table.update_item(
                Key={
                    'region': region,
                    'modelId': model_id
                },
                UpdateExpression='SET cacheDiscount = :discount',
                ExpressionAttributeValues={
                    ':discount': cache_discount
                }
            )
            print(f"Updated {region}/{model_id} with cache discount: {cache_discount}")
            
        except Exception as e:
            print(f"Failed to update {region}/{model_id}: {e}")

if __name__ == '__main__':
    update_model_pricing_with_cache()
    print("Cache discount update completed!")
