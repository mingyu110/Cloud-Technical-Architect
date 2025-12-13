#!/usr/bin/env python3
"""
Bedrock cost tracking Lambda function with dual mode support
"""
import json
import boto3
import os
import time
import logging
from decimal import Decimal
from typing import Dict, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize AWS clients with retry configuration
bedrock_runtime = boto3.client('bedrock-runtime', config=boto3.session.Config(
    retries={'max_attempts': 3}
))
dynamodb = boto3.resource('dynamodb')
resource_groups_tagging_api = boto3.client('resourcegroupstaggingapi', config=boto3.session.Config(
    retries={'max_attempts': 3}
))
cloudwatch = boto3.client('cloudwatch')
events = boto3.client('events')

# Cache configurations
TENANT_CONFIG_CACHE = {}
MODEL_PRICING_CACHE = {}
ARN_CACHE = {}
CONFIG_CACHE_TTL = 300  # 5 minutes
PRICING_CACHE_TTL = 3600  # 1 hour
ARN_CACHE_TTL = 3600  # 1 hour


def get_from_cache(cache: Dict, key: str, current_time: float):
    """Get value from cache if not expired"""
    if key in cache:
        entry = cache[key]
        if current_time - entry.get('expiry', 0) < 0:
            return entry['value']
        else:
            del cache[key]
    return None


def put_to_cache(cache: Dict, key: str, value: Any, ttl: int):
    """Store value in cache with TTL"""
    cache[key] = {
        'value': value,
        'expiry': time.time() + ttl
    }


def get_tenant_config(tenant_id: str) -> Dict[str, Any]:
    """
    Get tenant configuration from DynamoDB

    Cache: 5 minutes TTL
    """
    cached = get_from_cache(TENANT_CONFIG_CACHE, tenant_id, CONFIG_CACHE_TTL)
    if cached:
        return cached

    table_name = os.environ.get('TENANT_CONFIGS_TABLE', 'bedrock-cost-tracking-production-tenant-configs')
    table = dynamodb.Table(table_name)
    response = table.get_item(
        Key={'tenantId': tenant_id},
        ConsistentRead=False
    )

    if 'Item' not in response:
        raise ValueError(f"Tenant {tenant_id} not found")

    config = response['Item']
    put_to_cache(TENANT_CONFIG_CACHE, tenant_id, config, CONFIG_CACHE_TTL)
    return config


def get_inference_profile_arn(tenant_id: str, application_id: str) -> Optional[str]:
    """
    Get inference profile ARN using Resource Groups API

    Returns:
        str: Inference profile ARN if found
        None: If no inference profile configured (enables direct mode)
    """
    cache_key = f"{tenant_id}#{application_id}"

    # Check cache
    cached = get_from_cache(ARN_CACHE, cache_key, time.time())
    if cached:
        return cached

    # Call Resource Groups API
    try:
        response = resource_groups_tagging_api.get_resources(
            ResourceTypeFilters=['bedrock'],
            TagFilters=[
                {'Key': 'TenantID', 'Values': [tenant_id]},
                {'Key': 'ApplicationID', 'Values': [application_id]},
                {'Key': 'ModelType', 'Values': ['nova']}  # Only get Nova profiles
            ]
        )

        if not response.get('ResourceTagMappingList'):
            logger.info(f"No inference profile found for tenant {tenant_id}, app {application_id} - using direct mode")
            return None

        arn = response['ResourceTagMappingList'][0]['ResourceARN']

        # Cache result
        put_to_cache(ARN_CACHE, cache_key, arn, ARN_CACHE_TTL)

        return arn

    except Exception as e:
        logger.error(f"Resource Groups API failed: {e}")
        return None


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


def estimate_cost(model_id: str, input_tokens: int, output_tokens: int) -> float:
    """Estimate cost for budget checking"""
    try:
        pricing = get_model_pricing('us-east-1', model_id)
        input_cost_value = float(pricing['inputCost'])
        output_cost_value = float(pricing['outputCost'])
        
        input_cost = input_tokens * input_cost_value / 1000000
        output_cost = output_tokens * output_cost_value / 1000000
        
        return input_cost + output_cost
    except Exception as e:
        logger.warning(f"Failed to get pricing for {model_id}, using fallback: {e}")
        # Fallback pricing
        return (input_tokens * 0.00025 + output_tokens * 0.00125) / 1000


def check_budget(tenant_id: str, estimated_cost: float) -> bool:
    """
    Check budget before calling Bedrock

    Args:
        tenant_id: Tenant identifier
        estimated_cost: Estimated cost for the call

    Returns:
        True if budget is sufficient, False otherwise
    """
    try:
        table_name = os.environ.get('TENANT_BUDGETS_TABLE', 'bedrock-cost-tracking-production-tenant-budgets')
        table = dynamodb.Table(table_name)
        response = table.get_item(
            Key={'tenantId': tenant_id, 'modelId': 'ALL'},
            ProjectionExpression='balance, totalBudget, alertThreshold'
        )

        if 'Item' not in response:
            logger.info(f"No budget found for tenant {tenant_id}, allowing call")
            return True

        item = response['Item']
        balance = float(item['balance'])

        if balance >= estimated_cost:
            alert_threshold = float(item.get('alertThreshold', 0.8))
            utilization = balance / float(item['totalBudget'])

            if utilization < (1 - alert_threshold):
                logger.warning(f"Budget low for {tenant_id}: {utilization:.1%} remaining")

            return True
        else:
            logger.warning(f"Insufficient budget for {tenant_id}: ${balance:.4f} < ${estimated_cost:.4f}")
            return False

    except Exception as e:
        logger.error(f"Budget check failed for {tenant_id}: {e}")
        return True  # Degrade gracefully


def update_budget(tenant_id: str, cost: float):
    """
    Update budget asynchronously - simplified version for main Lambda
    Detailed breakdown is handled in the cost management function.
    """
    try:
        from decimal import Decimal
        table_name = os.environ.get('TENANT_BUDGETS_TABLE', 'bedrock-cost-tracking-production-tenant-budgets')
        table = dynamodb.Table(table_name)
        table.update_item(
            Key={'tenantId': tenant_id, 'modelId': 'ALL'},
            UpdateExpression="""
                ADD balance :cost, totalInvocations :one 
                SET lastUpdated = :timestamp
            """,
            ExpressionAttributeValues={
                ':cost': Decimal(str(-cost)),  # Convert float to Decimal
                ':one': 1,
                ':timestamp': int(time.time())
            }
        )
        logger.info(f"Budget updated for {tenant_id}: -${cost:.4f}")

    except Exception as e:
        logger.error(f"Budget update failed for {tenant_id}: {e}")


def record_session_interaction(session_id: str, tenant_id: str, application_id: str, 
                             conversation_turn: int, prompt: str, response: str,
                             input_tokens: int, output_tokens: int, cost: float, 
                             duration: float, model_id: str):
    """Record session interaction to DynamoDB"""
    if not session_id:
        return
        
    try:
        table_name = os.environ.get('SESSIONS_TABLE', 'bedrock-cost-tracking-production-sessions')
        table = dynamodb.Table(table_name)
        
        table.put_item(
            Item={
                'sessionId': session_id,
                'timestamp': int(time.time()),
                'tenantId': tenant_id,
                'applicationId': application_id,
                'conversationTurn': conversation_turn,
                'prompt': prompt[:500],
                'response': response[:1000],
                'inputTokens': input_tokens,
                'outputTokens': output_tokens,
                'cost': Decimal(str(cost)),
                'duration': Decimal(str(duration)),
                'modelId': model_id
            }
        )
        logger.info(f"Session interaction recorded: {session_id} turn {conversation_turn}")
        
    except Exception as e:
        logger.error(f"Failed to record session interaction: {e}")


def log_emf_metrics(**metrics):
    """Log metrics using Embedded Metric Format with optimized dimensions"""
    # Optimized: Reduced from 6 to 3 dimensions for better CloudWatch reliability
    dimensions = [
        ["TenantID"],                           # Tenant-level aggregation
        ["TenantID", "ApplicationID", "ModelID"], # Core business dimension
        ["TenantID", "SessionID"]               # Session-level analysis
    ]
    
    emf_entry = {
        "_aws": {
            "Timestamp": int(time.time() * 1000),
            "CloudWatchMetrics": [
                {
                    "Namespace": "BedrockCostManagement",
                    "Dimensions": dimensions,
                    "Metrics": [
                        {"Name": "InputTokens", "Unit": "Count"},
                        {"Name": "OutputTokens", "Unit": "Count"},
                        {"Name": "CacheReadTokens", "Unit": "Count"},
                        {"Name": "CacheWriteTokens", "Unit": "Count"},
                        {"Name": "InvocationCost", "Unit": "None"},
                        {"Name": "InvocationCount", "Unit": "Count"}
                    ]
                }
            ]
        },
        "TenantID": metrics['tenant_id'],
        "ApplicationID": metrics['application_id'],
        "ModelID": metrics['model_id'],
        "InputTokens": metrics['input_tokens'],
        "OutputTokens": metrics['output_tokens'],
        "CacheReadTokens": metrics.get('cache_read_tokens', 0),
        "CacheWriteTokens": metrics.get('cache_write_tokens', 0),
        "InvocationCost": round(metrics['cost'], 6),
        "InvocationCount": 1
    }
    
    if metrics.get('session_id'):
        emf_entry["SessionID"] = metrics['session_id']
    
    print(json.dumps(emf_entry))


def calculate_cost_with_cache(model_id: str, usage_data: dict) -> dict:
    """Calculate actual cost with caching breakdown"""
    input_tokens = usage_data.get('inputTokens', 0)
    output_tokens = usage_data.get('outputTokens', 0)
    cache_read_tokens = usage_data.get('cacheReadInputTokens', 0)
    cache_write_tokens = usage_data.get('cacheWriteInputTokens', 0)
    
    pricing = get_model_pricing('us-east-1', model_id)
    input_cost_value = float(pricing['inputCost'])
    output_cost_value = float(pricing['outputCost'])
    cache_discount = float(pricing.get('cacheDiscount', 0.5))
    
    # Calculate detailed costs
    cache_read_cost = cache_read_tokens * input_cost_value * cache_discount / 1000000
    cache_write_cost = cache_write_tokens * input_cost_value / 1000000
    regular_input_tokens = input_tokens - cache_read_tokens - cache_write_tokens
    regular_input_cost = regular_input_tokens * input_cost_value / 1000000
    output_cost = output_tokens * output_cost_value / 1000000
    
    total_cost = cache_read_cost + cache_write_cost + regular_input_cost + output_cost
    
    return {
        'totalCost': total_cost,
        'breakdown': {
            'cacheReadCost': cache_read_cost,
            'cacheWriteCost': cache_write_cost,
            'regularInputCost': regular_input_cost,
            'outputCost': output_cost
        }
    }


def publish_cost_event(event_bus_name: str, tenant_id: str, application_id: str,
                       model_id: str, input_tokens: int, output_tokens: int, actual_cost: float,
                       cache_read_tokens: int = 0, cache_write_tokens: int = 0, session_id: str = None):
    """
    Publish cost tracking event to EventBridge with caching and session support
    """
    try:
        enable_cost_tracking = os.environ.get('ENABLE_COST_TRACKING', 'true').lower() == 'true'
        if not enable_cost_tracking:
            logger.info("Cost tracking disabled, skipping event publication")
            return

        event_detail = {
            'tenantId': tenant_id,
            'applicationId': application_id,
            'modelId': model_id,
            'inputTokens': input_tokens,
            'outputTokens': output_tokens,
            'cacheReadTokens': cache_read_tokens,
            'cacheWriteTokens': cache_write_tokens,
            'cost': actual_cost,
            'timestamp': int(time.time())
        }
        
        if session_id:
            event_detail['sessionId'] = session_id

        response = events.put_events(
            Entries=[{
                'Source': 'bedrock.invocation',
                'DetailType': 'BedrockInvocationCost',
                'Detail': json.dumps(event_detail),
                'EventBusName': event_bus_name
            }]
        )

        logger.info(f"Cost event published for {tenant_id}: {response}")

    except Exception as e:
        logger.error(f"Failed to publish cost event: {e}")


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Enhanced Lambda handler supporting dual mode:
    1. Inference Profile mode: Precise cost management  
    2. Direct mode: Simple Bedrock calls
    """
    start_time = time.time()
    
    try:
        logger.info(f"Processing request: {json.dumps(event)}")

        # 1. Parse tenant ID from header (API Gateway passes it as x-tenant-id)
        tenant_id = event.get('headers', {}).get('x-tenant-id')
        if not tenant_id:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Missing x-tenant-id header'})
            }

        # 2. Idempotency protection - check if request already processed
        from idempotency_protection import get_request_id, check_idempotency, store_idempotency_result
        request_id = get_request_id(event)
        cached_response = check_idempotency(request_id, tenant_id)
        if cached_response:
            return cached_response

        # 2. Parse request body
        body = json.loads(event.get('body', '{}'))
        application_id = body.get('applicationId')
        prompt = body.get('prompt')
        requested_model = body.get('model')
        session_id = body.get('sessionId')
        conversation_turn = body.get('conversationTurn', 1)

        # 3. Get tenant config
        config = get_tenant_config(tenant_id)

        # 4. Validate requested model
        if requested_model:
            allowed_models_raw = config.get('allowedModels', [])
            if isinstance(allowed_models_raw, list):
                allowed_models = [m if isinstance(m, str) else m.get('S', '') for m in allowed_models_raw]
            else:
                allowed_models = [m.get('S', '') for m in allowed_models_raw.get('L', [])]
            
            if requested_model not in allowed_models:
                return {
                    'statusCode': 403,
                    'body': json.dumps({'error': f'Model {requested_model} not allowed for tenant'})
                }
            model_id = requested_model
        else:
            model_id = config['defaultModelId']

        # 5. Check for inference profile (dual mode decision point)
        inference_profile_arn = get_inference_profile_arn(tenant_id, application_id)
        
        if inference_profile_arn is None:
            # MODE 2: Direct mode - simple processing
            logger.info(f"Using direct mode for {tenant_id}/{application_id}")
            
            response = bedrock_runtime.converse(
                modelId=model_id,
                messages=[{
                    'role': 'user',
                    'content': [{'text': prompt}]
                }]
            )

            result = response['output']['message']['content'][0]['text']
            usage = response['usage']
            input_tokens = usage['inputTokens']
            output_tokens = usage['outputTokens']

            estimated_cost = estimate_cost(model_id, input_tokens, output_tokens)
            duration = time.time() - start_time

            response = {
                'statusCode': 200,
                'body': json.dumps({
                    'response': result,
                    'inputTokens': input_tokens,
                    'outputTokens': output_tokens,
                    'cost': estimated_cost,
                    'costManagement': False,
                    'mode': 'direct',
                    'duration': duration,
                    'model': model_id
                })
            }
            
            # Store for idempotency
            store_idempotency_result(request_id, tenant_id, response)
            return response

        # MODE 1: Inference profile mode - full cost management
        logger.info(f"Using inference profile mode for {tenant_id}/{application_id}")

        # 6. Estimate cost
        estimated_input_tokens = len(prompt.split()) * 1.3
        estimated_output_tokens = estimated_input_tokens * 0.8
        estimated_cost = estimate_cost(model_id, estimated_input_tokens, estimated_output_tokens)

        # 7. Check budget
        if not check_budget(tenant_id, estimated_cost):
            return {
                'statusCode': 402,
                'body': json.dumps({
                    'error': 'Budget exceeded',
                    'tenantId': tenant_id,
                    'estimatedCost': estimated_cost
                })
            }

        # 8. Call Bedrock with inference profile
        response = bedrock_runtime.converse(
            modelId=inference_profile_arn,
            messages=[{
                'role': 'user',
                'content': [{'text': prompt}]
            }],
            system=[{
                'text': "You are a helpful AI assistant."
            }]
        )

        # 9. Extract usage with caching support
        result = response['output']['message']['content'][0]['text']
        usage = response['usage']
        input_tokens = usage['inputTokens']
        output_tokens = usage['outputTokens']
        cache_read_tokens = usage.get('cacheReadInputTokens', 0)
        cache_write_tokens = usage.get('cacheWriteInputTokens', 0)

        # 10. Calculate actual cost with caching
        cost_breakdown = calculate_cost_with_cache(model_id, usage)
        actual_cost = cost_breakdown['totalCost']

        # 11. Update budget
        update_budget(tenant_id, actual_cost)

        # 12. Log metrics
        log_emf_metrics(
            tenant_id=tenant_id,
            application_id=application_id,
            model_id=model_id,
            session_id=session_id,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            cache_read_tokens=cache_read_tokens,
            cache_write_tokens=cache_write_tokens,
            cost=actual_cost
        )

        # 13. Record session interaction
        duration = time.time() - start_time
        record_session_interaction(
            session_id, tenant_id, application_id, conversation_turn,
            prompt, result, input_tokens, output_tokens, actual_cost, duration, model_id
        )

        # 14. Publish event to EventBridge
        publish_cost_event(
            event_bus_name=os.environ.get('EVENT_BUS_NAME', 'default'),
            tenant_id=tenant_id,
            application_id=application_id,
            model_id=model_id,
            session_id=session_id,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            actual_cost=actual_cost,
            cache_read_tokens=cache_read_tokens,
            cache_write_tokens=cache_write_tokens
        )

        # 15. Return response
        response = {
            'statusCode': 200,
            'body': json.dumps({
                'response': result,
                'inputTokens': input_tokens,
                'outputTokens': output_tokens,
                'cacheReadTokens': cache_read_tokens,
                'cacheWriteTokens': cache_write_tokens,
                'cost': actual_cost,
                'costManagement': True,
                'mode': 'inference_profile',
                'sessionId': session_id,
                'conversationTurn': conversation_turn,
                'duration': duration,
                'model': model_id
            })
        }
        
        # Store for idempotency
        store_idempotency_result(request_id, tenant_id, response)
        return response

    except Exception as e:
        logger.error(f"Error: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
