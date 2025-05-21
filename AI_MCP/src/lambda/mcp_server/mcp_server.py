import json
import logging
import os
import requests
import time
import sys
import pkgutil

# 配置日志
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# 添加Lambda Layer路径
lambda_task_root = os.environ.get('LAMBDA_TASK_ROOT', '')
layer_path = '/opt/python'
if os.path.exists(layer_path):
    logger.info(f"添加Layer路径: {layer_path}")
    sys.path.insert(0, layer_path)

# 添加调试信息
logger.info(f"Python版本: {sys.version}")
logger.info(f"Python路径: {sys.path}")
logger.info(f"环境变量: {dict(os.environ)}")
available_modules = [name for _, name, _ in pkgutil.iter_modules()]
logger.info(f"可用模块列表: {available_modules}")

# 尝试导入MCP服务器
try:
    # 使用AWS Lambda适配器
    from mcp.server.stdio import StdioServerParameters
    from mcp_lambda.stdio_server_adapter import stdio_server_adapter
    logger.info("成功导入MCP服务器和Lambda适配器")
    USE_MCP_SERVER = True
except ImportError as e:
    logger.error(f"导入MCP服务器失败: {str(e)}")
    USE_MCP_SERVER = False
    # 创建一个模拟的Context类作为后备
    class Context:
        def __init__(self):
            pass
        def info(self, message):
            logger.info(message)
        def warning(self, message):
            logger.warning(message)
        def error(self, message):
            logger.error(message)

# 环境变量
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')
MOCK_API_URL = os.environ.get('MOCK_API_URL')

# 验证环境变量
if not MOCK_API_URL:
    logger.warning("MOCK_API_URL环境变量未设置，使用默认值 http://localhost")
    MOCK_API_URL = "http://localhost"

# 定义获取订单状态的函数
async def get_order_status(order_id: str, ctx = None) -> str:
    """
    获取订单状态
    
    参数:
        order_id (str): 订单ID
        ctx: 上下文对象，提供用户信息和日志等功能
        
    返回:
        str: 订单状态信息
    """
    if ctx:
        ctx.info(f"Getting status for order ID: {order_id}")
    else:
        logger.info(f"Getting status for order ID: {order_id}")
    
    # 调用模拟订单API（带重试逻辑）
    max_retries = 3
    retry_delay = 1  # 初始延迟1秒
    
    for attempt in range(max_retries):
        try:
            payload = {"order_id": order_id}
            response = requests.post(MOCK_API_URL, json=payload, timeout=5)
            
            # 检查响应状态
            if response.status_code == 200:
                data = response.json()
                status = data.get('status', '未知')
                details = data.get('details', '')
                status_text = f"订单 {data.get('order_id', order_id)} 的状态是: {status}"
                if details:
                    status_text += f"，{details}"
                return status_text
            else:
                error_msg = f"API返回错误: {response.status_code}"
                if ctx:
                    ctx.warning(error_msg)
                else:
                    logger.warning(error_msg)
                    
                # 如果不是最后一次尝试，进行重试
                if attempt < max_retries - 1:
                    retry_msg = f"将在{retry_delay}秒后进行第{attempt + 2}次尝试"
                    if ctx:
                        ctx.info(retry_msg)
                    else:
                        logger.info(retry_msg)
                    time.sleep(retry_delay)
                    retry_delay *= 2  # 指数退避策略
                else:
                    if ctx:
                        ctx.error(f"在{max_retries}次尝试后仍然失败")
                    else:
                        logger.error(f"在{max_retries}次尝试后仍然失败")
                    return f"无法获取订单 {order_id} 的状态，系统错误。"
                    
        except Exception as e:
            error_msg = f"调用订单API时出错: {str(e)}"
            if ctx:
                ctx.warning(error_msg)
            else:
                logger.warning(error_msg)
                
            # 如果不是最后一次尝试，进行重试
            if attempt < max_retries - 1:
                retry_msg = f"将在{retry_delay}秒后进行第{attempt + 2}次尝试"
                if ctx:
                    ctx.info(retry_msg)
                else:
                    logger.info(retry_msg)
                time.sleep(retry_delay)
                retry_delay *= 2  # 指数退避策略
            else:
                if ctx:
                    ctx.error(f"在{max_retries}次尝试后仍然失败")
                else:
                    logger.error(f"在{max_retries}次尝试后仍然失败")
                return f"无法获取订单 {order_id} 的状态，服务暂时不可用。"

def create_server_adapter():
    """创建MCP服务器适配器"""
    if USE_MCP_SERVER:
        try:
            # 创建服务器适配器
            from mcp.tool import tool, Context, Annotated
            from mcp.server.stdio import create_server
            
            # 使用工具装饰器定义工具
            @tool("get_order_status")
            async def get_order_status_tool(
                order_id: str,
                ctx: Annotated[Context, Context]
            ) -> str:
                """获取订单状态信息"""
                return await get_order_status(order_id, ctx)
            
            # 创建stdio服务器
            server = create_server(tools=[get_order_status_tool])
            
            # 创建Lambda适配器
            adapter = stdio_server_adapter(
                server_parameters=StdioServerParameters(),
                server_factory=lambda: server
            )
            
            logger.info("成功创建MCP服务器适配器")
            return adapter
        except Exception as e:
            logger.error(f"创建MCP服务器适配器时出错: {str(e)}")
            # 返回一个简单的处理函数作为后备
            return lambda event, context: {
                "statusCode": 500,
                "body": json.dumps({
                    "error": f"创建MCP服务器适配器失败: {str(e)}"
                })
            }
    else:
        logger.warning("使用后备处理函数，不支持标准MCP协议")
        # 返回一个简单的处理函数作为后备
        return lambda event, context: handle_request_fallback(event, context)

def handle_request_fallback(event, context):
    """后备请求处理函数"""
    logger.info(f"使用后备处理函数处理请求: {event}")
    try:
        # 解析请求体
        if 'body' in event and event['body']:
            body = json.loads(event['body'])
            tool_name = body.get('tool_name')
            params = body.get('params', {})
            
            if tool_name == 'get_order_status':
                order_id = params.get('order_id', '12345')
                # 同步调用get_order_status
                import asyncio
                result = asyncio.run(get_order_status(order_id))
                return {
                    "statusCode": 200,
                    "body": json.dumps({
                        "result": result
                    })
                }
            else:
                return {
                    "statusCode": 400,
                    "body": json.dumps({
                        "error": f"不支持的工具: {tool_name}"
                    })
                }
        
        return {
            "statusCode": 400,
            "body": json.dumps({
                "error": "无效的请求格式"
            })
        }
    except Exception as e:
        logger.error(f"处理请求时出错: {str(e)}")
        return {
            "statusCode": 500,
            "body": json.dumps({
                "error": f"服务器内部错误: {str(e)}"
            })
        }

# 创建Lambda处理函数
handler = create_server_adapter()

# 添加与Lambda期望一致的入口点
def lambda_handler(event, context):
    return handler(event, context) 