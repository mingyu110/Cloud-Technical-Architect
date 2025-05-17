import json
import logging
import os
import boto3
import requests
from botocore.config import Config

# 配置日志
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# 环境变量
ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")
MCP_SERVER_URL = os.environ.get("MCP_SERVER_URL", "http://localhost")
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
MODEL_ID = os.environ.get("MODEL_ID", "anthropic.claude-v2")

# 初始化Bedrock运行时客户端
bedrock_runtime = boto3.client(
    service_name="bedrock-runtime",
    region_name=AWS_REGION,
    config=Config(retries={"max_attempts": 10})
)

def get_order_status(order_id):
    """获取订单状态"""
    try:
        payload = {
            "tool_name": "get_order_status",
            "params": {"order_id": order_id}
        }
        response = requests.post(MCP_SERVER_URL, json=payload, timeout=10)
        if response.status_code == 200:
            return response.json().get("result", "")
        else:
            return f"无法获取订单 {order_id} 的状态，系统错误。"
    except Exception as e:
        logger.error(f"调用MCP服务器时出错: {str(e)}")
        return f"无法获取订单 {order_id} 的状态，服务暂时不可用。"

def extract_order_id_from_query(query):
    """从用户查询中提取订单ID"""
    import re
    
    # 尝试匹配订单ID
    patterns = [
        r"订单\s*(?:号|ID|编号)?\s*[:#：]?\s*(\d+)",
        r"(?:订单|单号)[:#：]?\s*(\d+)",
        r"[#＃]\s*(\d+)"
    ]
    
    for pattern in patterns:
        match = re.search(pattern, query)
        if match:
            return match.group(1)
    
    # 如果没有匹配，返回默认值
    return "12345"

def generate_response_with_bedrock(context, query):
    """
    使用AWS Bedrock生成响应
    
    参数:
        context (str): 上下文信息（如订单状态）
        query (str): 用户查询
        
    返回:
        str: LLM生成的响应
    """
    try:
        # 准备提示
        prompt = f"Human: 你是一个订单助手，可以帮助客户查询订单状态。你只能回答与订单相关的问题。\n\n上下文信息：\n{context}\n\n客户问题：{query}"
        logger.info(f"发送到Bedrock的提示: {prompt}")
        
        # 调用Bedrock
        request_body = json.dumps({
            "prompt": prompt,
            "max_tokens_to_sample": 500,
            "temperature": 0.7,
            "stop_sequences": ["\n\nHuman:"]
        })
        
        response = bedrock_runtime.invoke_model(
            body=request_body,
            modelId=MODEL_ID,
            accept="application/json",
            contentType="application/json"
        )
        
        # 解析响应
        response_body = json.loads(response.get("body").read())
        ai_response = response_body.get("completion", "")
        logger.info(f"Bedrock响应: {ai_response}")
        
        return ai_response
        
    except Exception as e:
        error_msg = f"调用Bedrock时出错: {str(e)}"
        logger.error(error_msg)
        return "很抱歉，我现在无法回答您的问题。请稍后再试。"

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
    
    try:
        # 从请求体提取用户查询
        if "body" in event and event["body"]:
            body = json.loads(event["body"])
            query = body.get("query", "")
            
            if not query:
                return {
                    "statusCode": 400,
                    "headers": {"Content-Type": "application/json"},
                    "body": json.dumps({"error": "缺少query参数"})
                }
            
            # 从查询中提取订单ID
            order_id = extract_order_id_from_query(query)
            logger.info(f"从查询中提取的订单ID: {order_id}")
            
            # 1. 使用MCP客户端连接MCP服务器
            # 2. 调用get_order_status工具获取订单状态
            order_status = get_order_status(order_id)
            logger.info(f"获取到的订单状态: {order_status}")
            
            # 3. 将订单状态作为上下文传递给Bedrock
            # 4. 使用AWS Bedrock生成自然语言响应
            ai_response = generate_response_with_bedrock(order_status, query)
            
            # 5. 返回生成的响应给用户
            response_body = {
                "response": ai_response,
                "query": query,
                "extracted_order_id": order_id
            }
            
            return {
                "statusCode": 200,
                "headers": {
                    "Content-Type": "application/json",
                    "Access-Control-Allow-Origin": "*"
                },
                "body": json.dumps(response_body, ensure_ascii=False)
            }
            
        # 处理未经身份验证的根路径OPTIONS请求（CORS支持）
        elif event.get("httpMethod") == "OPTIONS":
            return {
                "statusCode": 200,
                "headers": {
                    "Content-Type": "application/json",
                    "Access-Control-Allow-Origin": "*",
                    "Access-Control-Allow-Headers": "Content-Type,Authorization",
                    "Access-Control-Allow-Methods": "OPTIONS,POST"
                },
                "body": json.dumps({})
            }
        else:
            return {
                "statusCode": 400,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"error": "请求体为空或格式不正确"})
            }
            
    except Exception as e:
        logger.error(f"处理请求时出错: {str(e)}")
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": f"服务器内部错误: {str(e)}"})
        }
