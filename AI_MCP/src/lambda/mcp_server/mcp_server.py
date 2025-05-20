import json
import logging
import os
import requests
import time

# 配置日志
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# 尝试多种可能的导入路径
try:
    # 主要导入路径
    from mcpengine import MCPEngine, Context
    logger.info("成功从mcpengine导入MCPEngine和Context")
except ImportError as e:
    logger.error(f"从mcpengine导入MCPEngine和Context失败: {str(e)}")
    try:
        # 尝试替代导入路径
        from mcpengine.server import MCPEngine
        from mcpengine.context import Context
        logger.info("成功从mcpengine.server和mcpengine.context导入")
    except ImportError as e2:
        logger.error(f"替代导入路径也失败: {str(e2)}")
        try:
            # 尝试导入Lambda专用包
            from mcpengine.lambda_context import Context
            from mcpengine import MCPEngine
            logger.info("成功导入MCPEngine和lambda_context.Context")
        except ImportError as e3:
            logger.error(f"所有导入尝试均失败: {str(e3)}")
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
            
            # 创建一个简化的MCPEngine作为后备
            class MCPEngine:
                def __init__(self, name=None, debug=False):
                    self.name = name
                    self.debug = debug
                    logger.warning(f"使用模拟的MCPEngine: {name}, debug={debug}")
                
                def tool(self):
                    def decorator(func):
                        return func
                    return decorator
                
                def get_lambda_handler(self):
                    def handler(event, context):
                        logger.error("使用模拟的Lambda处理器，无法处理请求")
                        return {
                            "statusCode": 500,
                            "body": json.dumps({
                                "error": "MCPEngine导入失败，请检查依赖安装"
                            })
                        }
                    return handler

# 环境变量
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')
MOCK_API_URL = os.environ.get('MOCK_API_URL')

# 验证环境变量
if not MOCK_API_URL:
    logger.warning("MOCK_API_URL环境变量未设置，使用默认值 http://localhost")
    MOCK_API_URL = "http://localhost"

# 创建MCP服务器实例 - 配置为使用Context7
engine = MCPEngine(
    name="OrderStatusMCP",  # 为服务器命名，便于识别
    debug=ENVIRONMENT == "dev"  # 在开发环境下启用调试模式
)

@engine.tool()
async def get_order_status(order_id: str, ctx: Context = None) -> str:
    """
    获取订单状态
    
    参数:
        order_id (str): 订单ID
        ctx (Context): 上下文对象，提供用户信息和日志等功能
        
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

# 使用MCPEngine内置的Lambda处理器
handler = engine.get_lambda_handler() 

# 添加与Lambda期望一致的入口点
def lambda_handler(event, context):
    return handler(event, context) 