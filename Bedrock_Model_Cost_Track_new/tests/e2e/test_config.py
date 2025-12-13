#!/usr/bin/env python3
"""
E2E测试配置文件 - 集中管理所有测试配置
"""

# API配置
API_CONFIG = {
    "url": "https://tor8uppsc3.execute-api.us-east-1.amazonaws.com/production/invoke",
    "timeout": 60,
    "max_retries": 3,
    "retry_delay": 5
}

# 模型配置
MODEL_CONFIG = {
    "default_model": "amazon.nova-pro-v1:0",
    "alternative_models": [
        "amazon.nova-lite-v1:0",
        "amazon.nova-micro-v1:0"
    ]
}

# 租户配置
TENANT_CONFIG = {
    "demo1": {
        "tenant_id": "demo1",
        "app_id": "websearch",
        "cost_threshold": 0.01,
        "token_threshold": 1000,
        "alarm_names": {
            "cost": "Demo1-Cost-Alert-5min-0.01USD",
            "token": "Demo1-Token-Alert-5min-1000"
        }
    },
    "demo2": {
        "tenant_id": "demo2",
        "app_id": "chatbot",
        "cost_threshold": 0.002,
        "token_threshold": 1000,
        "alarm_names": {
            "cost": "Demo2-Cost-Alert-5min-0.002USD",
            "token": "Demo2-Token-Alert-5min-1000"
        }
    }
}

# 测试配置
TEST_CONFIG = {
    "wait_between_tests": 60,
    "alarm_trigger_delay": 180,  # 3分钟
    "verbose_output": False
}

# CloudWatch配置
CLOUDWATCH_CONFIG = {
    "region": "us-east-1",
    "log_group": "/aws/lambda/cost-management-lambda",
    "metric_namespace": "BedrockCostManagement"
}

# 提示词配置
PROMPT_CONFIG = {
    "long": {
        "name": "长提示词",
        "description": "用于触发Token告警",
        "estimated_tokens": 1500
    },
    "medium": {
        "name": "中等提示词",
        "description": "用于触发成本告警",
        "estimated_tokens": 800
    },
    "short": {
        "name": "短提示词",
        "description": "用于基础测试",
        "estimated_tokens": 200
    }
}

def get_tenant_config(tenant_id: str) -> dict:
    """获取租户配置
    
    Args:
        tenant_id: 租户ID
        
    Returns:
        dict: 租户配置
        
    Raises:
        ValueError: 如果租户ID不存在
    """
    if tenant_id not in TENANT_CONFIG:
        raise ValueError(f"未知的租户ID: {tenant_id}")
    return TENANT_CONFIG[tenant_id]

def get_alarm_name(tenant_id: str, alarm_type: str) -> str:
    """获取告警名称
    
    Args:
        tenant_id: 租户ID
        alarm_type: 告警类型 ('cost' 或 'token')
        
    Returns:
        str: 告警名称
    """
    config = get_tenant_config(tenant_id)
    return config["alarm_names"][alarm_type]

def get_threshold(tenant_id: str, threshold_type: str) -> float:
    """获取阈值
    
    Args:
        tenant_id: 租户ID
        threshold_type: 阈值类型 ('cost' 或 'token')
        
    Returns:
        float: 阈值
    """
    config = get_tenant_config(tenant_id)
    return config[f"{threshold_type}_threshold"]

# 导出常用配置
API_URL = API_CONFIG["url"]
DEFAULT_MODEL = MODEL_CONFIG["default_model"]
REQUEST_TIMEOUT = API_CONFIG["timeout"]
MAX_RETRIES = API_CONFIG["max_retries"]
RETRY_DELAY = API_CONFIG["retry_delay"]
