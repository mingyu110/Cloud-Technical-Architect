import json
import logging
import os

# 配置日志
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# 环境变量
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')

def lambda_handler(event, context):
    """
    模拟订单状态API
    
    参数:
        event (dict): API Gateway事件
        context (object): Lambda上下文
        
    返回:
        dict: 带有状态码和响应体的字典
    """
    logger.info(f"Received event: {json.dumps(event)}")
    
    # 从请求中获取订单ID
    try:
        # 首先尝试从请求体获取
        if 'body' in event and event['body']:
            body = json.loads(event['body'])
            order_id = body.get('order_id', '')
        # 其次尝试从查询字符串参数获取
        elif 'queryStringParameters' in event and event['queryStringParameters'] and 'order_id' in event['queryStringParameters']:
            order_id = event['queryStringParameters']['order_id']
        # 最后尝试从路径参数获取
        elif 'pathParameters' in event and event['pathParameters'] and 'order_id' in event['pathParameters']:
            order_id = event['pathParameters']['order_id']
        else:
            order_id = '12345'  # 默认订单ID
    except Exception as e:
        logger.error(f"Error parsing request: {str(e)}")
        order_id = '12345'  # 默认订单ID
    
    logger.info(f"Looking up status for order ID: {order_id}")
    
    # 模拟订单数据
    mock_data = {
        "12345": "已发货",
        "67890": "待处理",
        "24680": "已付款",
        "13579": "配送中",
        "99999": "未找到"
    }
    
    # 查找订单状态
    status = mock_data.get(order_id, "未找到")
    
    # 构建响应
    response_body = {
        'order_id': order_id,
        'status': status,
        'environment': ENVIRONMENT
    }
    
    # 返回API Gateway格式的响应
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(response_body, ensure_ascii=False)
    } 