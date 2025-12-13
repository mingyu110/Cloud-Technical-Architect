#!/usr/bin/env python3
"""
Bedrock cost tracking Lambda function with dual mode support
Redis + DynamoDB hybrid storage for high performance
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
    retries={'max_attempts': 3},
    connect_timeout=5,
    read_timeout=60
))
dynamodb = boto3.resource('dynamodb')
resource_groups_tagging_api = boto3.client('resourcegroupstaggingapi', config=boto3.session.Config(
    retries={'max_attempts': 2},
    connect_timeout=3,
    read_timeout=10
))
sqs = boto3.client('sqs', config=boto3.session.Config(
    retries={'max_attempts': 2},
    connect_timeout=3,
    read_timeout=10
))

# Import Redis cache module
from redis_cache import get_from_redis, set_to_redis

# Cache TTL configurations
CONFIG_CACHE_TTL = 300  # 5 minutes
PRICING_CACHE_TTL = 3600  # 1 hour
ARN_CACHE_TTL = 3600  # 1 hour


def get_tenant_config(tenant_id: str) -> Dict[str, Any]:
    """
    Get tenant configuration with Redis Cache-Aside pattern
    
    Flow:
    1. Check Redis cache (< 1ms)
    2. If miss, query DynamoDB (5-10ms)
    3. Write back to Redis
    
    Cache TTL: 5 minutes
    """
    # 1. Try Redis first
    cache_key = f"tenant_config:{tenant_id}"
    cached = get_from_redis(cache_key)
    if cached:
        logger.debug(f"Redis cache hit: {cache_key}")
        return cached

    # 2. Redis miss, query DynamoDB
    logger.debug(f"Redis cache miss: {cache_key}, querying DynamoDB")
    table_name = os.environ.get('TENANT_CONFIGS_TABLE', 'bedrock-cost-tracking-production-tenant-configs')
    table = dynamodb.Table(table_name)
    response = table.get_item(
        Key={'tenantId': tenant_id},
        ConsistentRead=False
    )

    if 'Item' not in response:
        raise ValueError(f"Tenant {tenant_id} not found")

    config = response['Item']
    
    # 3. Write back to Redis
    set_to_redis(cache_key, config, CONFIG_CACHE_TTL)
    
    return config


def get_inference_profile_arn(tenant_id: str, application_id: str) -> Optional[str]:
    """
    Get inference profile ARN using Resource Groups API with Redis cache
    
    Returns:
        str: Inference profile ARN if found
        None: If no inference profile configured (enables direct mode)
    
    Cache TTL: 1 hour
    """
    cache_key = f"inference_profile_arn:{tenant_id}:{application_id}"

    # 1. Try Redis first
    cached = get_from_redis(cache_key)
    if cached is not None:
        logger.debug(f"Redis cache hit: {cache_key}")
        return cached.get('arn')

    # 2. Redis miss, call Resource Groups API
    logger.debug(f"Redis cache miss: {cache_key}, calling Resource Groups API")
    try:
        response = resource_groups_tagging_api.get_resources(
            ResourceTypeFilters=['bedrock'],
            TagFilters=[
                {'Key': 'TenantID', 'Values': [tenant_id]},
                {'Key': 'ApplicationID', 'Values': [application_id]},
                {'Key': 'ModelType', 'Values': ['nova']}
            ]
        )

        if not response.get('ResourceTagMappingList'):
            logger.info(f"No inference profile found for {tenant_id}/{application_id} - using direct mode")
            arn = None
        else:
            arn = response['ResourceTagMappingList'][0]['ResourceARN']
            logger.info(f"Found inference profile: {arn}")

        # 3. Write back to Redis
        set_to_redis(cache_key, {'arn': arn}, ARN_CACHE_TTL)

        return arn

    except Exception as e:
        logger.error(f"Resource Groups API failed: {e}, using direct mode")
        return None


def get_model_pricing(region: str, model_id: str) -> Dict[str, float]:
    """
    Get model pricing with Redis Cache-Aside pattern
    
    Flow:
    1. Check Redis cache (< 1ms)
    2. If miss, query DynamoDB (5-10ms)
    3. Write back to Redis
    
    Cache TTL: 1 hour
    """
    # 1. Try Redis first
    cache_key = f"model_pricing:{region}:{model_id}"
    cached = get_from_redis(cache_key)
    if cached:
        logger.debug(f"Redis cache hit: {cache_key}")
        return cached

    # 2. Redis miss, query DynamoDB
    logger.debug(f"Redis cache miss: {cache_key}, querying DynamoDB")
    table_name = os.environ.get('MODEL_PRICING_TABLE', 'bedrock-cost-tracking-production-model-pricing')
    table = dynamodb.Table(table_name)
    response = table.get_item(
        Key={'region': region, 'modelId': model_id}
    )

    if 'Item' not in response:
        raise ValueError(f"Pricing not found for {region}/{model_id}")

    pricing = response['Item']
    
    # 3. Write back to Redis
    set_to_redis(cache_key, pricing, PRICING_CACHE_TTL)

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
    Check budget before calling Bedrock with Redis Cache-Aside pattern
    
    Flow:
    1. Check Redis cache (< 1ms)
    2. If miss, query DynamoDB (5-10ms)
    3. Write back to Redis
    
    Args:
        tenant_id: Tenant identifier
        estimated_cost: Estimated cost for the call

    Returns:
        True if budget is sufficient, False otherwise
    
    Cache TTL: 5 minutes (balance changes frequently)
    """
    try:
        # 1. Try Redis first
        cache_key = f"tenant_budget:{tenant_id}"
        cached = get_from_redis(cache_key)
        
        if cached:
            logger.debug(f"Redis cache hit: {cache_key}")
            budget_data = cached
        else:
            # 2. Redis miss, query DynamoDB
            logger.debug(f"Redis cache miss: {cache_key}, querying DynamoDB")
            table_name = os.environ.get('TENANT_BUDGETS_TABLE', 'bedrock-cost-tracking-production-tenant-budgets')
            table = dynamodb.Table(table_name)
            response = table.get_item(
                Key={'tenantId': tenant_id, 'modelId': 'ALL'},
                ProjectionExpression='balance, totalBudget, alertThreshold'
            )

            if 'Item' not in response:
                logger.info(f"No budget found for tenant {tenant_id}, allowing call")
                return True

            budget_data = response['Item']
            
            # 3. Write back to Redis (shorter TTL since balance changes)
            set_to_redis(cache_key, budget_data, CONFIG_CACHE_TTL)

        # Check budget
        balance = float(budget_data['balance'])

        if balance >= estimated_cost:
            alert_threshold = float(budget_data.get('alertThreshold', 0.8))
            utilization = balance / float(budget_data['totalBudget'])

            if utilization < (1 - alert_threshold):
                logger.warning(f"Budget low for {tenant_id}: {utilization:.1%} remaining")

            return True
        else:
            logger.warning(f"Insufficient budget for {tenant_id}: ${balance:.4f} < ${estimated_cost:.4f}")
            return False

    except Exception as e:
        logger.error(f"Budget check failed for {tenant_id}: {e}")
        return True  # Degrade gracefully


# Budget deduction is handled by cost management Lambda (async)
# No need to update or invalidate cache here - cost management Lambda will do it after deduction





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


def publish_cost_event(queue_url: str, tenant_id: str, application_id: str,
                       model_id: str, input_tokens: int, output_tokens: int, actual_cost: float,
                       cache_read_tokens: int = 0, cache_write_tokens: int = 0, session_id: str = None,
                       request_id: str = None, session_data: dict = None):
    """
    Send cost tracking message to SQS queue with idempotency token and optional session data
    """
    try:
        enable_cost_tracking = os.environ.get('ENABLE_COST_TRACKING', 'true').lower() == 'true'
        if not enable_cost_tracking:
            logger.info("Cost tracking disabled, skipping message send")
            return

        # Generate idempotency token (for consumer-side deduplication)
        idempotency_token = request_id or f"{tenant_id}:{application_id}:{int(time.time() * 1000)}"
        
        message_body = {
            'idempotencyToken': idempotency_token,  # For consumer deduplication
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
            message_body['sessionId'] = session_id
        
        if session_data:
            message_body['sessionData'] = session_data

        response = sqs.send_message(
            QueueUrl=queue_url,
            MessageBody=json.dumps(message_body)
        )

        logger.info(f"Cost message sent to SQS for {tenant_id}: MessageId={response['MessageId']}")

    except Exception as e:
        logger.error(f"Failed to send cost message to SQS: {e}")



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
        
        # Support both old and new message formats
        application_id = body.get('applicationId', 'default-app')
        session_id = body.get('sessionId')
        conversation_turn = body.get('conversationTurn', 1)
        
        # Get model ID
        model_id = body.get('modelId')
        if not model_id:
            model_id = body.get('model')
        
        # Get messages 
        messages = body.get('messages')
        if not messages:
            #  prompt
            prompt = body.get('prompt', '')
            if prompt:
                messages = [{'role': 'user', 'content': [{'text': prompt}]}]
        
        if not messages:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Missing messages or prompt'})
            }

        # 3. Get tenant config
        logger.info(f"Getting tenant config for {tenant_id}")
        config = get_tenant_config(tenant_id)
        logger.info(f"Tenant config retrieved")

        # 4. Use model from request or default
        if not model_id:
            model_id = config.get('defaultModelId', 'anthropic.claude-3-sonnet-20240229-v1:0')

        # 5. Check for inference profile (dual mode decision point)
        logger.info(f"Checking inference profile for {tenant_id}/{application_id}")
        inference_profile_arn = get_inference_profile_arn(tenant_id, application_id)
        logger.info(f"Inference profile result: {inference_profile_arn}")
        
        if inference_profile_arn is None:
            # MODE 2: Direct mode - simple processing
            logger.info(f"Using direct mode for {tenant_id}/{application_id}")
            
            logger.info(f"Calling Bedrock with modelId: {model_id}")
            
            # Prepare converse API parameters
            converse_params = {
                'modelId': model_id,
                'messages': messages
            }
            
            # Add optional parameters from body
            if 'max_tokens' in body:
                converse_params['inferenceConfig'] = {'maxTokens': body['max_tokens']}
            if 'system' in body:
                converse_params['system'] = body['system']
            
            response = bedrock_runtime.converse(**converse_params)
            logger.info(f"Bedrock response received")

            result = response['output']['message']['content'][0]['text']
            usage = response['usage']
            input_tokens = usage['inputTokens']
            output_tokens = usage['outputTokens']

            estimated_cost = estimate_cost(model_id, input_tokens, output_tokens)
            duration = time.time() - start_time
            
            # Prepare session data for async recording
            session_data = None
            if session_id:
                # Extract prompt from messages
                prompt = ""
                if messages and len(messages) > 0:
                    content = messages[0].get('content', [])
                    if content and len(content) > 0:
                        prompt = content[0].get('text', '')[:500]
                
                session_data = {
                    'conversationTurn': conversation_turn,
                    'prompt': prompt,
                    'response': result[:1000],
                    'duration': duration
                }
            
            # Send cost event to SQS
            publish_cost_event(
                queue_url=os.environ.get('COST_EVENT_QUEUE_URL'),
                tenant_id=tenant_id,
                application_id=application_id,
                model_id=model_id,
                input_tokens=input_tokens,
                output_tokens=output_tokens,
                actual_cost=estimated_cost,
                session_id=session_id,
                request_id=request_id,
                session_data=session_data
            )

            response_body = {
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
            store_idempotency_result(request_id, tenant_id, response_body)
            return response_body

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
        logger.info(f"Calling Bedrock with inference profile: {inference_profile_arn}")
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
        logger.info(f"Bedrock response received from inference profile")

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

        # 11. Budget deduction is handled by cost management Lambda (async)
        # No cache invalidation here - cost management Lambda will invalidate after deduction

        # 12. Metrics are published by cost management Lambda (via SQS)
        # Removed EMF logging here to avoid duplication and improve performance

        # 13. Prepare session data for async recording
        duration = time.time() - start_time
        session_data = None
        if session_id:
            session_data = {
                'conversationTurn': conversation_turn,
                'prompt': prompt[:500],
                'response': result[:1000],
                'duration': duration
            }

        # 14. Send cost message to SQS
        publish_cost_event(
            queue_url=os.environ.get('COST_EVENT_QUEUE_URL'),
            tenant_id=tenant_id,
            application_id=application_id,
            model_id=model_id,
            session_id=session_id,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            actual_cost=actual_cost,
            cache_read_tokens=cache_read_tokens,
            cache_write_tokens=cache_write_tokens,
            session_data=session_data
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
