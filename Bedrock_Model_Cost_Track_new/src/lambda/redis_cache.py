#!/usr/bin/env python3
"""
Redis cache layer for high-performance data access
Implements Cache-Aside pattern with automatic fallback to DynamoDB
"""
import json
import os
import logging
from typing import Optional, Dict, Any

logger = logging.getLogger()

# Lazy initialization
_redis_client = None


def get_redis_client():
    """Get or create Redis client with lazy initialization"""
    global _redis_client
    
    if _redis_client is None:
        redis_endpoint = os.environ.get('REDIS_ENDPOINT')
        if not redis_endpoint:
            logger.warning("REDIS_ENDPOINT not configured, Redis cache disabled")
            return None
        
        try:
            import redis
            # Parse host:port
            if ':' in redis_endpoint:
                host, port = redis_endpoint.rsplit(':', 1)
                port = int(port)
            else:
                host = redis_endpoint
                port = 6379
            
            _redis_client = redis.Redis(
                host=host,
                port=port,
                decode_responses=True,
                socket_connect_timeout=1,
                socket_timeout=1,
                socket_keepalive=True,
                health_check_interval=30
            )
            # Test connection
            _redis_client.ping()
            logger.info(f"Redis connected: {redis_endpoint}")
        except Exception as e:
            logger.error(f"Redis connection failed: {e}")
            _redis_client = None
    
    return _redis_client


def get_from_redis(key: str) -> Optional[Dict[str, Any]]:
    """
    Get value from Redis cache
    
    Returns:
        Dict if found, None if not found or error
    """
    client = get_redis_client()
    if not client:
        return None
    
    try:
        value = client.get(key)
        if value:
            return json.loads(value)
        return None
    except Exception as e:
        logger.warning(f"Redis GET failed for {key}: {e}")
        return None


def set_to_redis(key: str, value: Dict[str, Any], ttl: int = 300):
    """
    Set value to Redis cache with TTL
    
    Args:
        key: Cache key
        value: Value to cache (will be JSON serialized)
        ttl: Time to live in seconds (default: 5 minutes)
    """
    client = get_redis_client()
    if not client:
        return
    
    try:
        client.setex(key, ttl, json.dumps(value, default=str))
    except Exception as e:
        logger.warning(f"Redis SET failed for {key}: {e}")


def delete_from_redis(key: str):
    """Delete key from Redis cache"""
    client = get_redis_client()
    if not client:
        return
    
    try:
        client.delete(key)
    except Exception as e:
        logger.warning(f"Redis DELETE failed for {key}: {e}")


def invalidate_pattern(pattern: str):
    """
    Invalidate all keys matching pattern
    
    Args:
        pattern: Redis key pattern (e.g., "tenant_config:*")
    """
    client = get_redis_client()
    if not client:
        return
    
    try:
        keys = client.keys(pattern)
        if keys:
            client.delete(*keys)
            logger.info(f"Invalidated {len(keys)} keys matching {pattern}")
    except Exception as e:
        logger.warning(f"Redis pattern invalidation failed for {pattern}: {e}")
