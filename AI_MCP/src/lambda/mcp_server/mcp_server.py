import json
import logging
import os
import requests
from mcp.server.fastmcp import FastMCP

# 配置日志
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# 环境变量
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')
MOCK_API_URL = os.environ.get('MOCK_API_URL', 'http://localhost')

# 创建MCP服务器实例
mcp = FastMCP("order_status_server")

@mcp.tool()
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

def lambda_handler(event, context):
    """
    Lambda处理函数，处理来自API Gateway的请求
    
    参数:
        event (dict): API Gateway事件
        context (object): Lambda上下文
        
    返回:
        dict: 带有状态码和响应体的字典
    """
    logger.info(f"Received event: {json.dumps(event)}")
    
    # 从请求体提取MCP调用参数
    try:
        if 'body' in event and event['body']:
            body = json.loads(event['body'])
            tool_name = body.get('tool_name', '')
            params = body.get('params', {})
            
            # 验证请求
            if not tool_name:
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': '缺少tool_name参数'}),
                }
            
            # 检查是否是列出工具的请求
            if tool_name == "__list_tools__":
                tools_info = [
                    {
                        "name": "get_order_status",
                        "description": "获取订单状态",
                        "parameters": {
                            "order_id": {
                                "type": "string",
                                "description": "订单ID"
                            }
                        },
                        "return_type": "string"
                    }
                ]
                return {
                    'statusCode': 200,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({'tools': tools_info})
                }
            
            # 调用MCP工具
            if tool_name == "get_order_status":
                order_id = params.get('order_id', '12345')
                # 这里简化处理，在实际代码中应使用FastMCP的异步API
                # result = await mcp.call_tool("get_order_status", {"order_id": order_id})
                
                # 直接调用函数而不使用FastMCP框架
                payload = {"order_id": order_id}
                response = requests.post(MOCK_API_URL, json=payload, timeout=5)
                
                if response.status_code == 200:
                    data = response.json()
                    status = data.get('status', '未知')
                    result = f"订单 {data.get('order_id', order_id)} 的状态是: {status}"
                else:
                    result = f"无法获取订单 {order_id} 的状态，系统错误。"
                
                return {
                    'statusCode': 200,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({'result': result})
                }
            else:
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': f'未知工具: {tool_name}'})
                }
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': '请求体为空'})
            }
    except Exception as e:
        logger.error(f"处理请求时出错: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': f'服务器内部错误: {str(e)}'})
        } 