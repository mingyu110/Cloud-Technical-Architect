#!/usr/bin/env python3
"""
Idempotency protection for Lambda functions
"""
import json
import boto3
import time
import logging
from typing import Dict, Any, Optional
from botocore.exceptions import ClientError

logger = logging.getLogger()
dynamodb = boto3.resource('dynamodb')

# DynamoDB table for idempotency tracking
IDEMPOTENCY_TABLE = 'BedrockCostTrackingIdempotency'

def get_request_id(event: Dict[str, Any]) -> str:
    """Extract request ID for idempotency key"""
    # For API Gateway requests
    if 'requestContext' in event:
        return event['requestContext'].get('requestId', '')
    
    # Fallback to generating from event content
    import hashlib
    content = json.dumps(event, sort_keys=True)
    return hashlib.md5(content.encode()).hexdigest()

def check_idempotency(request_id: str, tenant_id: str) -> Optional[Dict]:
    """Check if request was already processed"""
    try:
        table = dynamodb.Table(IDEMPOTENCY_TABLE)
        response = table.get_item(
            Key={
                'RequestId': request_id,
                'TenantId': tenant_id
            }
        )
        
        if 'Item' in response:
            item = response['Item']
            # Check if not expired (24 hour TTL)
            if time.time() < item.get('ExpiresAt', 0):
                logger.info(f"Request {request_id} already processed, returning cached result")
                return json.loads(item.get('Response', '{}'))
        
        return None
    except Exception as e:
        logger.warning(f"Failed to check idempotency: {e}")
        return None

def store_idempotency_result(request_id: str, tenant_id: str, response: Dict):
    """Store successful response for idempotency"""
    try:
        table = dynamodb.Table(IDEMPOTENCY_TABLE)
        expires_at = int(time.time()) + 86400  # 24 hours
        
        table.put_item(
            Item={
                'RequestId': request_id,
                'TenantId': tenant_id,
                'Response': json.dumps(response),
                'ProcessedAt': int(time.time()),
                'ExpiresAt': expires_at
            },
            ConditionExpression='attribute_not_exists(RequestId)'
        )
        logger.info(f"Stored idempotency result for request {request_id}")
    except ClientError as e:
        if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
            logger.info(f"Request {request_id} already stored by concurrent execution")
        else:
            logger.warning(f"Failed to store idempotency result: {e}")
    except Exception as e:
        logger.warning(f"Failed to store idempotency result: {e}")


