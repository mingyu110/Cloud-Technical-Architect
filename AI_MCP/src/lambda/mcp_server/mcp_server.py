import json
import logging
import os
import requests
from mcpengine import MCPEngine

# 配置日志
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# 环境变量
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')
MOCK_API_URL = os.environ.get('MOCK_API_URL', 'http://localhost')

# 创建MCP服务器实例
engine = MCPEngine()

@engine.tool()
async def get_order_status(order_id: str) -> str:
    """
    获取订单状态
    
    参数:
        order_id (str): 订单ID
        
    返回:
        str: 订单状态信息
    """
    logger.info(f"Getting status for order ID: {order_id}")
    
    # 调用模拟订单API
    try:
        payload = {"order_id": order_id}
        response = requests.post(MOCK_API_URL, json=payload, timeout=5)
        
        # 检查响应状态
        if response.status_code == 200:
            data = response.json()
            status = data.get('status', '未知')
            return f"订单 {data.get('order_id', order_id)} 的状态是: {status}"
        else:
            logger.error(f"API返回错误: {response.status_code}")
            return f"无法获取订单 {order_id} 的状态，系统错误。"
    except Exception as e:
        logger.error(f"调用订单API时出错: {str(e)}")
        return f"无法获取订单 {order_id} 的状态，服务暂时不可用。"

# 使用MCPEngine内置的Lambda处理器
handler = engine.get_lambda_handler() 