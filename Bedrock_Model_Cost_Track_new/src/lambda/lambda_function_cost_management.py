"""
Amazon Bedrock Cost Management Function

This Lambda function handles cost tracking, budget management, and metrics logging
asynchronously via SQS messages from the main Bedrock invocation function.

Triggered by: SQS queue (batch processing up to 10 messages)
"""

import json
import boto3
import time
import os
from typing import Dict, Any, Optional, List
from botocore.config import Config
import logging
from decimal import Decimal
import hashlib

# Logger setup
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Global AWS clients (reuse across invocations)
dynamodb = boto3.resource('dynamodb')
cloudwatch = boto3.client('cloudwatch')
sns = boto3.client('sns')

# Cache configurations
MODEL_PRICING_CACHE: Dict[str, Any] = {}
IDEMPOTENCY_CACHE: Dict[str, float] = {}  # token -> timestamp

# Cache TTL
PRICING_CACHE_TTL = 86400  # 24 hours for pricing
IDEMPOTENCY_TTL = 300  # 5 minutes for idempotency


def check_idempotency(token: str) -> bool:
    """Check if message already processed (5-minute window)"""
    if token in IDEMPOTENCY_CACHE:
        if time.time() - IDEMPOTENCY_CACHE[token] < IDEMPOTENCY_TTL:
            return True  # Already processed
        else:
            del IDEMPOTENCY_CACHE[token]  # Expired
    return False


def mark_processed(token: str):
    """Mark message as processed"""
    IDEMPOTENCY_CACHE[token] = time.time()
    
    # Clean up expired entries
    expired = [k for k, v in IDEMPOTENCY_CACHE.items() if time.time() - v > IDEMPOTENCY_TTL]
    for k in expired:
        del IDEMPOTENCY_CACHE[k]


def get_from_cache(cache: Dict, key: str, ttl: float) -> Optional[Any]:
    """Get value from cache if not expired"""
    if key in cache:
        entry = cache[key]
        if time.time() < entry['expiry']:
            return entry['value']
    return None


def put_to_cache(cache: Dict, key: str, value: Any, ttl: int):
    """Store value in cache with TTL"""
    cache[key] = {
        'value': value,
        'expiry': time.time() + ttl
    }


def get_model_pricing(region: str, model_id: str) -> Dict[str, float]:
    """Get model pricing from DynamoDB"""
    cache_key = f"{region}#{model_id}"

    cached = get_from_cache(MODEL_PRICING_CACHE, cache_key, time.time())
    if cached:
        return cached

    table_name = os.environ.get('MODEL_PRICING_TABLE', 'bedrock-cost-tracking-production-model-pricing')
    table = dynamodb.Table(table_name)
    response = table.get_item(
        Key={'region': region, 'modelId': model_id}
    )

    if 'Item' not in response:
        raise ValueError(f"Pricing not found for {region}/{model_id}")

    pricing = response['Item']
    put_to_cache(MODEL_PRICING_CACHE, cache_key, pricing, PRICING_CACHE_TTL)

    return pricing


def update_tenant_budget(tenant_id: str, model_id: str, input_tokens: int, output_tokens: int, cost: float,
                        cache_read_tokens: int = 0, cache_write_tokens: int = 0):
    """
    Update tenant budget with detailed breakdown including caching metrics

    IMPORTANT: This is the ONLY function that deducts budget balance.
    The main Lambda only checks budget and invalidates cache.
    
    This function updates both:
    1. Tenant total summary (modelId='ALL') - deducts balance and updates token stats
    2. Model-specific breakdown (modelId=actual_model) - tracks per-model usage

    Args:
        tenant_id: Tenant identifier
        model_id: Model identifier
        input_tokens: Number of input tokens
        output_tokens: Number of output tokens
        cost: Calculated cost
        cache_read_tokens: Number of tokens read from cache
        cache_write_tokens: Number of tokens written to cache
    """
    try:
        table_name = os.environ.get('TENANT_BUDGETS_TABLE', 'bedrock-cost-tracking-production-tenant-budgets')
        table = dynamodb.Table(table_name)

        # 1. Update tenant total summary
        table.update_item(
            Key={'tenantId': tenant_id, 'modelId': 'ALL'},
            UpdateExpression="""
                SET balance = balance - :cost,
                    totalInputTokens = if_not_exists(totalInputTokens, :zero) + :input_tokens,
                    totalOutputTokens = if_not_exists(totalOutputTokens, :zero) + :output_tokens,
                    totalCacheReadTokens = if_not_exists(totalCacheReadTokens, :zero) + :cache_read_tokens,
                    totalCacheWriteTokens = if_not_exists(totalCacheWriteTokens, :zero) + :cache_write_tokens,
                    totalInvocations = if_not_exists(totalInvocations, :zero) + :one,
                    lastUpdated = :timestamp
            """,
            ExpressionAttributeValues={
                ':cost': Decimal(str(cost)),
                ':input_tokens': input_tokens,
                ':output_tokens': output_tokens,
                ':cache_read_tokens': cache_read_tokens,
                ':cache_write_tokens': cache_write_tokens,
                ':one': 1,
                ':zero': 0,
                ':timestamp': int(time.time())
            },
            ConditionExpression='balance >= :cost'
        )

        # 2. Update model-specific breakdown
        table.update_item(
            Key={'tenantId': tenant_id, 'modelId': model_id},
            UpdateExpression="""
                SET balance = if_not_exists(balance, :zero) - :cost,
                    totalInputTokens = if_not_exists(totalInputTokens, :zero) + :input_tokens,
                    totalOutputTokens = if_not_exists(totalOutputTokens, :zero) + :output_tokens,
                    totalCacheReadTokens = if_not_exists(totalCacheReadTokens, :zero) + :cache_read_tokens,
                    totalCacheWriteTokens = if_not_exists(totalCacheWriteTokens, :zero) + :cache_write_tokens,
                    totalInvocations = if_not_exists(totalInvocations, :zero) + :one,
                    lastUpdated = :timestamp
            """,
            ExpressionAttributeValues={
                ':cost': Decimal(str(cost)),
                ':input_tokens': input_tokens,
                ':output_tokens': output_tokens,
                ':cache_read_tokens': cache_read_tokens,
                ':cache_write_tokens': cache_write_tokens,
                ':one': 1,
                ':zero': 0,
                ':timestamp': int(time.time())
            }
        )

        cache_info = f" (cache: {cache_read_tokens}R/{cache_write_tokens}W)" if cache_read_tokens or cache_write_tokens else ""
        logger.info(f"Budget updated for {tenant_id}/{model_id}: -${cost:.4f}{cache_info}")

    except Exception as e:
        logger.error(f"Budget update failed for {tenant_id}/{model_id}: {e}")
        raise


def log_detailed_emf_metrics(tenant_id: str, application_id: str, model_id: str, session_id: str,
                           input_tokens: int, output_tokens: int, 
                           cache_read_tokens: int, cache_write_tokens: int, cost: float):
    """
    Log detailed EMF metrics for cost management with caching and session support

    This function logs more detailed metrics than the main Lambda,
    including cost per token, efficiency metrics, cache efficiency, session metrics, etc.
    """
    try:
        # Calculate derived metrics
        total_tokens = input_tokens + output_tokens
        cost_per_token = cost / total_tokens if total_tokens > 0 else 0
        output_ratio = output_tokens / input_tokens if input_tokens > 0 else 0
        
        # Cache efficiency metrics
        cache_hit_ratio = cache_read_tokens / input_tokens if input_tokens > 0 else 0
        cache_efficiency = (cache_read_tokens + cache_write_tokens) / input_tokens if input_tokens > 0 else 0

        # Base dimensions
        dimensions = [
            ["TenantID"],
            ["TenantID", "ModelID"],
            ["TenantID", "ApplicationID"],
            ["TenantID", "ApplicationID", "ModelID"]
        ]
        
        # Add session dimensions if session_id is provided
        if session_id:
            dimensions.extend([
                ["SessionID"],
                ["TenantID", "SessionID"],
                ["TenantID", "ApplicationID", "SessionID"]
            ])

        emf_entry = {
            "_aws": {
                "Timestamp": int(time.time() * 1000),
                "CloudWatchMetrics": [
                    {
                        "Namespace": "BedrockCostManagement",
                        "Dimensions": dimensions,
                        "Metrics": [
                            {"Name": "DetailedCost", "Unit": "None"},
                            {"Name": "InputTokens", "Unit": "Count"},
                            {"Name": "OutputTokens", "Unit": "Count"},
                            {"Name": "TotalTokens", "Unit": "Count"},
                            {"Name": "CacheReadTokens", "Unit": "Count"},
                            {"Name": "CacheWriteTokens", "Unit": "Count"},
                            {"Name": "CostPerToken", "Unit": "None"},
                            {"Name": "OutputRatio", "Unit": "None"},
                            {"Name": "CacheHitRatio", "Unit": "Percent"},
                            {"Name": "CacheEfficiency", "Unit": "Percent"},
                            {"Name": "ProcessingTime", "Unit": "Milliseconds"}
                        ]
                    }
                ]
            },
            "TenantID": tenant_id,
            "ApplicationID": application_id,
            "ModelID": model_id,
            "DetailedCost": round(cost, 6),
            "InputTokens": input_tokens,
            "OutputTokens": output_tokens,
            "TotalTokens": total_tokens,
            "CacheReadTokens": cache_read_tokens,
            "CacheWriteTokens": cache_write_tokens,
            "CostPerToken": round(cost_per_token, 8),
            "OutputRatio": round(output_ratio, 3),
            "CacheHitRatio": round(cache_hit_ratio * 100, 2),
            "CacheEfficiency": round(cache_efficiency * 100, 2),
            "ProcessingTime": int(time.time() * 1000)  # Current timestamp as processing time
        }
        
        # Add SessionID if provided
        if session_id:
            emf_entry["SessionID"] = session_id

        print(json.dumps(emf_entry))
        logger.info(f"Detailed metrics logged for {tenant_id}/{model_id} (cache hit: {cache_hit_ratio:.1%})")

    except Exception as e:
        logger.error(f"Failed to log detailed metrics: {e}")


def check_budget_alerts(tenant_id: str, cost: float):
    """
    Check if budget alerts should be triggered
    
    Uses smart throttling to avoid alert fatigue:
    - First alert: immediate
    - Subsequent alerts: only if utilization increases by 10% or 1 hour has passed

    Args:
        tenant_id: Tenant identifier
        cost: Cost of the current invocation
    """
    try:
        table_name = os.environ.get('TENANT_BUDGETS_TABLE', 'bedrock-cost-tracking-production-tenant-budgets')
        table = dynamodb.Table(table_name)
        response = table.get_item(
            Key={'tenantId': tenant_id, 'modelId': 'ALL'}
        )

        if 'Item' not in response:
            logger.warning(f"No budget found for tenant {tenant_id}")
            return

        item = response['Item']
        balance = float(item.get('balance', 0))
        total_budget = float(item.get('totalBudget', 0))
        alert_threshold = float(item.get('alertThreshold', 0.8))
        
        # Get last alert info
        last_alert_time = int(item.get('lastAlertTime', 0))
        last_alert_utilization = float(item.get('lastAlertUtilization', 0))

        if total_budget > 0:
            utilization = (total_budget - balance) / total_budget
            current_time = int(time.time())
            
            # Check if we've crossed the alert threshold
            if utilization >= alert_threshold:
                should_alert = False
                
                # First time alert
                if last_alert_time == 0:
                    should_alert = True
                    logger.info(f"First budget alert for {tenant_id}")
                
                # Alert if utilization increased by 10% or more
                elif utilization >= last_alert_utilization + 0.1:
                    should_alert = True
                    logger.info(f"Budget alert for {tenant_id}: utilization increased by {(utilization - last_alert_utilization):.1%}")
                
                # Alert if 1 hour has passed since last alert
                elif current_time - last_alert_time >= 3600:
                    should_alert = True
                    logger.info(f"Budget alert for {tenant_id}: 1 hour since last alert")
                
                if should_alert:
                    send_budget_alert(tenant_id, balance, total_budget, utilization)
                    
                    # Update last alert info
                    table.update_item(
                        Key={'tenantId': tenant_id, 'modelId': 'ALL'},
                        UpdateExpression="SET lastAlertTime = :time, lastAlertUtilization = :util",
                        ExpressionAttributeValues={
                            ':time': current_time,
                            ':util': Decimal(str(utilization))
                        }
                    )
                else:
                    logger.debug(f"Skipping alert for {tenant_id}: throttled (last alert {current_time - last_alert_time}s ago)")

    except Exception as e:
        logger.error(f"Budget alert check failed for {tenant_id}: {e}")


def get_model_budget(tenant_id: str, model_id: str) -> Optional[Dict]:
    """Get model-specific budget information"""
    try:
        table_name = os.environ.get('TENANT_BUDGETS_TABLE', 'bedrock-cost-tracking-production-tenant-budgets')
        table = dynamodb.Table(table_name)
        response = table.get_item(
            Key={'tenantId': tenant_id, 'modelId': model_id}
        )

        return response.get('Item')

    except Exception as e:
        logger.error(f"Failed to get model budget for {tenant_id}/{model_id}: {e}")
        return None


def get_tenant_usage_summary(tenant_id: str) -> Dict[str, Any]:
    """
    Get comprehensive usage summary for a tenant

    Returns:
        Dictionary with usage statistics across all models
    """
    try:
        table_name = os.environ.get('TENANT_BUDGETS_TABLE', 'bedrock-cost-tracking-production-tenant-budgets')
        table = dynamodb.Table(table_name)

        # Query all records for the tenant (using primary key)
        response = table.query(
            KeyConditionExpression='tenantId = :tenant_id',
            ExpressionAttributeValues={':tenant_id': tenant_id}
        )

        summary = {
            'tenantId': tenant_id,
            'totalCost': 0,
            'totalTokens': 0,
            'totalInvocations': 0,
            'modelBreakdown': {},
            'lastUpdated': 0
        }

        for item in response.get('Items', []):
            model_id = item['modelId']
            
            if model_id == 'ALL':
                # Overall tenant summary
                summary['totalCost'] = float(item.get('totalBudget', 0)) - float(item.get('balance', 0))
                summary['totalTokens'] = int(item.get('totalInputTokens', 0)) + int(item.get('totalOutputTokens', 0))
                summary['totalInvocations'] = int(item.get('totalInvocations', 0))
                summary['lastUpdated'] = int(item.get('lastUpdated', 0))
            else:
                # Model-specific breakdown
                summary['modelBreakdown'][model_id] = {
                    'cost': float(item.get('totalBudget', 0)) - float(item.get('balance', 0)),
                    'inputTokens': int(item.get('totalInputTokens', 0)),
                    'outputTokens': int(item.get('totalOutputTokens', 0)),
                    'invocations': int(item.get('totalInvocations', 0))
                }

        return summary

    except Exception as e:
        logger.error(f"Failed to get usage summary for {tenant_id}: {e}")
        return {'error': str(e)}


def send_budget_alert(tenant_id: str, balance: float, total_budget: float, utilization: float):
    """Send budget alert via SNS"""
    try:
        logger.warning(f"Budget alert for {tenant_id}: {utilization:.1%} utilized, ${balance:.2f} remaining")
        
        # Send SNS notification if topic ARN is configured
        topic_arn = os.environ.get('BUDGET_ALERT_TOPIC_ARN')
        if topic_arn:
            sns.publish(
                TopicArn=topic_arn,
                Message=f"""
预算告警通知

租户ID: {tenant_id}
预算使用率: {utilization:.1%}
总预算: ${total_budget:.2f}
剩余预算: ${balance:.2f}
告警时间: {time.strftime('%Y-%m-%d %H:%M:%S')}

建议: 请及时充值或优化使用以避免服务中断。
                """.strip(),
                Subject=f"预算告警 - {tenant_id} ({utilization:.0%})"
            )
            logger.info(f"Budget alert sent to SNS for {tenant_id}")
        else:
            logger.info("BUDGET_ALERT_TOPIC_ARN not configured, skipping SNS notification")

    except Exception as e:
        logger.error(f"Failed to send budget alert: {e}")


def record_session_interaction(session_id: str, tenant_id: str, application_id: str,
                              model_id: str, input_tokens: int, output_tokens: int,
                              cost: float, timestamp: int, session_data: dict):
    """Record session interaction to DynamoDB asynchronously"""
    if not session_id or not session_data:
        return
    
    try:
        table_name = os.environ.get('SESSIONS_TABLE', 'bedrock-cost-tracking-production-sessions')
        table = dynamodb.Table(table_name)
        
        table.put_item(
            Item={
                'sessionId': session_id,
                'timestamp': timestamp,
                'tenantId': tenant_id,
                'applicationId': application_id,
                'conversationTurn': session_data.get('conversationTurn', 1),
                'prompt': session_data.get('prompt', ''),
                'response': session_data.get('response', ''),
                'inputTokens': input_tokens,
                'outputTokens': output_tokens,
                'cost': Decimal(str(cost)),
                'duration': Decimal(str(session_data.get('duration', 0))),
                'modelId': model_id
            }
        )
        logger.info(f"Session interaction recorded: {session_id} turn {session_data.get('conversationTurn', 1)}")
        
    except Exception as e:
        logger.error(f"Failed to record session interaction: {e}")


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for cost management with idempotency and partial batch failure
    
    Processes SQS messages in batch (up to 10 messages per invocation)
    Returns batchItemFailures for failed messages (SQS will retry)
    """
    try:
        logger.info(f"Processing {len(event.get('Records', []))} SQS messages")
        
        batch_item_failures = []  # For partial batch failure reporting
        
        # Process each SQS message
        for record in event.get('Records', []):
            message_id = record['messageId']
            receipt_handle = record['receiptHandle']
            
            try:
                # Parse SQS message body
                message_body = json.loads(record['body'])
                
                # Idempotency check
                idempotency_token = message_body.get('idempotencyToken')
                if idempotency_token and check_idempotency(idempotency_token):
                    logger.info(f"Message {message_id} already processed (idempotency), skipping")
                    continue
                
                tenant_id = message_body.get('tenantId')
                application_id = message_body.get('applicationId')
                model_id = message_body.get('modelId')
                session_id = message_body.get('sessionId')
                session_data = message_body.get('sessionData')
                input_tokens = message_body.get('inputTokens', 0)
                output_tokens = message_body.get('outputTokens', 0)
                cache_read_tokens = message_body.get('cacheReadTokens', 0)
                cache_write_tokens = message_body.get('cacheWriteTokens', 0)
                cost = message_body.get('cost', 0.0)
                timestamp = message_body.get('timestamp', int(time.time()))

                if not all([tenant_id, application_id, model_id]):
                    raise ValueError("Missing required fields in message")

                # 1. Update tenant budget
                update_tenant_budget(tenant_id, model_id, input_tokens, output_tokens, cost, 
                                   cache_read_tokens, cache_write_tokens)

                # 2. Record session interaction (async)
                if session_id and session_data:
                    record_session_interaction(session_id, tenant_id, application_id, model_id,
                                             input_tokens, output_tokens, cost, timestamp, session_data)

                # 3. Log detailed EMF metrics
                log_detailed_emf_metrics(tenant_id, application_id, model_id, session_id, 
                                       input_tokens, output_tokens, cache_read_tokens, 
                                       cache_write_tokens, cost)

                # 4. Check for budget alerts
                check_budget_alerts(tenant_id, cost)
                
                # Mark as processed
                if idempotency_token:
                    mark_processed(idempotency_token)
                
                logger.info(f"Successfully processed message {message_id} for tenant {tenant_id}")
                
            except Exception as e:
                logger.error(f"Failed to process message {message_id}: {e}")
                # Add to batch item failures (SQS will retry)
                batch_item_failures.append({'itemIdentifier': message_id})

        # Return partial batch failure response
        return {
            'batchItemFailures': batch_item_failures
        }

    except Exception as e:
        logger.error(f"Batch processing failed: {e}")
        # Return all messages as failed (SQS will retry all)
        return {
            'batchItemFailures': [
                {'itemIdentifier': record['messageId']} 
                for record in event.get('Records', [])
            ]
        }
