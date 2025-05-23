import json
import logging
import os
import requests
import time
import sys
import uuid
import pkgutil
import asyncio
from typing import Dict, Any, Optional, List, Union
from fastapi import FastAPI, Request, Response, Depends, HTTPException
from fastapi.responses import StreamingResponse, JSONResponse
from mangum import Mangum
import uvicorn

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

# 环境变量
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')
MOCK_API_URL = os.environ.get('MOCK_API_URL')

# 验证环境变量
if not MOCK_API_URL:
    logger.warning("MOCK_API_URL环境变量未设置，使用默认值 http://localhost:8000")
    MOCK_API_URL = "http://localhost:8000"

# 创建FastAPI应用
app = FastAPI(
    title="MCP服务器", 
    description="基于Streamable HTTP的MCP服务器实现 (v2025.03.26)",
    version="1.0.0"
)

# 定义JSON-RPC响应格式
class JsonRpcResponse:
    @staticmethod
    def success(result: Any, id: Optional[Union[str, int]] = None) -> Dict[str, Any]:
        return {
            "jsonrpc": "2.0",
            "id": id or str(uuid.uuid4()),
            "result": result
        }
    
    @staticmethod
    def error(message: str, code: int = -32603, id: Optional[Union[str, int]] = None) -> Dict[str, Any]:
        return {
            "jsonrpc": "2.0",
            "id": id or str(uuid.uuid4()),
            "error": {
                "code": code,
                "message": message
            }
        }

# 会话管理
class MCPSession:
    def __init__(self, session_id: str):
        self.session_id = session_id
        self.created_at = time.time()
        self.last_access = time.time()
        self.tools = {
            "get_order_status": get_order_status,
            "__list_tools__": self.list_tools
        }
    
    def update_access(self):
        self.last_access = time.time()
    
    async def list_tools(self) -> Dict[str, Any]:
        """列出可用的工具"""
        tools = {}
        for name, func in self.tools.items():
            if name.startswith("__"):  # 跳过内部工具
                continue
            tools[name] = {
                "description": func.__doc__ or "No description available",
                "parameters": {}  # 在真实场景中，可以从函数签名中提取参数
            }
        return tools

# 会话存储
sessions = {}

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
    logger_prefix = "[Context] " if ctx else ""
    logger.info(f"{logger_prefix}获取订单ID的状态: {order_id}")
    
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
                logger.warning(error_msg)
                    
                # 如果不是最后一次尝试，进行重试
                if attempt < max_retries - 1:
                    retry_msg = f"将在{retry_delay}秒后进行第{attempt + 2}次尝试"
                    logger.info(retry_msg)
                    await asyncio.sleep(retry_delay)
                    retry_delay *= 2  # 指数退避策略
                else:
                    logger.error(f"在{max_retries}次尝试后仍然失败")
                    return f"无法获取订单 {order_id} 的状态，系统错误。"
                    
        except Exception as e:
            error_msg = f"调用订单API时出错: {str(e)}"
            logger.warning(error_msg)
                
            # 如果不是最后一次尝试，进行重试
            if attempt < max_retries - 1:
                retry_msg = f"将在{retry_delay}秒后进行第{attempt + 2}次尝试"
                logger.info(retry_msg)
                await asyncio.sleep(retry_delay)
                retry_delay *= 2  # 指数退避策略
            else:
                logger.error(f"在{max_retries}次尝试后仍然失败")
                return f"无法获取订单 {order_id} 的状态，服务暂时不可用。"

# 会话依赖
def get_session(request: Request) -> MCPSession:
    """获取或创建会话"""
    # 从请求头中获取会话ID
    session_id = request.headers.get("Mcp-Session-Id")
    
    # 如果没有会话ID，生成一个新的
    if not session_id:
        session_id = f"session_{time.time()}_{os.urandom(4).hex()}"
        logger.info(f"创建新会话: {session_id}")
        sessions[session_id] = MCPSession(session_id)
    # 如果会话不存在，创建一个新的
    elif session_id not in sessions:
        logger.info(f"重新创建会话: {session_id}")
        sessions[session_id] = MCPSession(session_id)
    # 更新会话访问时间
    else:
        sessions[session_id].update_access()
        
    return sessions[session_id]

# 会话清理任务
@app.on_event("startup")
async def start_session_cleanup():
    """定期清理过期会话"""
    async def cleanup_sessions():
        while True:
            try:
                await asyncio.sleep(300)  # 每5分钟清理一次
                current_time = time.time()
                expired_sessions = []
                
                for session_id, session in sessions.items():
                    # 如果超过30分钟未访问，认为会话已过期
                    if current_time - session.last_access > 1800:
                        expired_sessions.append(session_id)
                
                for session_id in expired_sessions:
                    logger.info(f"清理过期会话: {session_id}")
                    sessions.pop(session_id, None)
                
                logger.info(f"会话清理完成，当前会话数: {len(sessions)}")
            except Exception as e:
                logger.error(f"会话清理出错: {str(e)}")
    
    # 创建清理任务
    asyncio.create_task(cleanup_sessions())

@app.post("/mcp")
async def post_message(request: Request, session: MCPSession = Depends(get_session)) -> JSONResponse:
    """处理MCP消息（POST请求）- JSON-RPC 2.0格式"""
    try:
        # 解析请求体
        data = await request.json()
        request_id = data.get("id", str(uuid.uuid4()))
        logger.info(f"收到POST请求 (id: {request_id}): {data}")
        
        # 验证JSON-RPC 2.0格式
        if data.get("jsonrpc") != "2.0":
            logger.warning(f"请求不是有效的JSON-RPC 2.0格式: {data}")
            return JSONResponse(
                content=JsonRpcResponse.error(
                    "无效的JSON-RPC格式，需要jsonrpc: 2.0", 
                    code=-32600, 
                    id=request_id
                )
            )
        
        # 处理方法调用
        method = data.get("method")
        
        # 处理工具调用请求
        if method == "call_tool":
            params = data.get("params", {})
            tool_name = params.get("name")
            tool_args = params.get("params", {})
            
            # 验证参数
            if not tool_name:
                logger.warning(f"没有指定工具名称: {params}")
                return JSONResponse(
                    content=JsonRpcResponse.error(
                        "缺少工具名称", 
                        code=-32602, 
                        id=request_id
                    )
                )
            
            # 检查工具是否存在
            if tool_name not in session.tools:
                logger.warning(f"请求了未知工具: {tool_name}")
                return JSONResponse(
                    content=JsonRpcResponse.error(
                        f"未知工具: {tool_name}", 
                        code=404, 
                        id=request_id
                    )
                )
            
            # 调用工具并获取结果
            logger.info(f"调用工具 {tool_name} 参数: {tool_args}")
            try:
                result = await session.tools[tool_name](**tool_args)
                return JSONResponse(
                    content=JsonRpcResponse.success(result, id=request_id),
                    headers={"Mcp-Session-Id": session.session_id}
                )
            except Exception as e:
                logger.error(f"工具执行错误: {str(e)}")
                return JSONResponse(
                    content=JsonRpcResponse.error(
                        f"工具执行错误: {str(e)}", 
                        code=-32603, 
                        id=request_id
                    ),
                    headers={"Mcp-Session-Id": session.session_id}
                )
        else:
            logger.warning(f"未知的请求方法: {method}")
            return JSONResponse(
                content=JsonRpcResponse.error(
                    f"不支持的方法: {method}", 
                    code=-32601, 
                    id=request_id
                ),
                headers={"Mcp-Session-Id": session.session_id}
            )
            
    except json.JSONDecodeError as e:
        logger.error(f"JSON解析错误: {str(e)}")
        return JSONResponse(
            content=JsonRpcResponse.error("无效的JSON格式", code=-32700),
            status_code=400
        )
    except Exception as e:
        logger.error(f"处理请求时出错: {str(e)}")
        return JSONResponse(
            content=JsonRpcResponse.error(f"服务器内部错误: {str(e)}", code=-32603),
            status_code=500
        )

@app.get("/mcp")
async def get_message(request: Request, session: MCPSession = Depends(get_session)):
    """处理MCP消息（GET请求）- 支持SSE流式传输"""
    logger.info(f"收到GET请求，启动SSE流: {session.session_id}")
    
    async def sse_stream():
        """SSE流生成器"""
        # 发送连接成功事件
        yield f"event: connected\ndata: {json.dumps({'session_id': session.session_id})}\n\n"
        
        try:
            # 保持连接活跃的心跳
            while True:
                await asyncio.sleep(30)  # 30秒发送一次心跳
                yield f"event: heartbeat\ndata: {json.dumps({'timestamp': time.time()})}\n\n"
        except asyncio.CancelledError:
            logger.info(f"SSE流已取消: {session.session_id}")
        except Exception as e:
            logger.error(f"SSE流出错: {str(e)}")
    
    return StreamingResponse(
        sse_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
            "Mcp-Session-Id": session.session_id
        }
    )

@app.options("/mcp")
async def options_mcp():
    """处理OPTIONS请求，支持CORS"""
    return Response(
        content="",
        headers={
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, Mcp-Session-Id",
            "Access-Control-Max-Age": "86400"  # 24小时
        }
    )

@app.get("/health")
async def health_check():
    """健康检查接口"""
    return {
        "status": "healthy",
        "timestamp": time.time(),
        "environment": ENVIRONMENT,
        "sessions": len(sessions)
    }

# 使用Mangum适配器转换FastAPI应用为Lambda处理函数
handler = Mangum(app)

# Lambda处理函数入口点
def lambda_handler(event, context):
    """AWS Lambda处理函数"""
    logger.info(f"收到Lambda事件类型: {type(event)}")
    logger.info(f"收到Lambda事件: {event[:1000] if isinstance(event, str) else event}")
    return handler(event, context)

# 如果直接运行脚本，启动开发服务器
if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000) 