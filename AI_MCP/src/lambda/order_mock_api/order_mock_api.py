import json
import logging
import os

# 配置日志
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# 环境变量
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')

# 模拟订单数据库
MOCK_ORDERS = {
    "12345": {"status": "已发货", "details": "预计3天内送达"},
    "54321": {"status": "已付款", "details": "等待发货"},
    "98765": {"status": "配送中", "details": "正在派送"},
    "67890": {"status": "已完成", "details": "感谢您的购买"}
}

def lambda_handler(event, context):
    """订单状态模拟API，能够处理不同的订单ID"""
    
    try:
        # 提取请求体中的order_id
        order_id = None
        if event.get("body"):
            try:
                body = json.loads(event["body"])
                order_id = body.get("order_id")
            except json.JSONDecodeError:
                logger.error("无效的JSON请求体")
                return {
                    "statusCode": 400,
                    "headers": {"Content-Type": "application/json"},
                    "body": json.dumps({"error": "请求体必须是有效的JSON"})
                }
        
        # 如果没有order_id，返回错误
        if not order_id:
            logger.warning("请求中缺少order_id参数")
            return {
                "statusCode": 400,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"error": "缺少order_id参数"})
            }
        
        # 查找订单信息
        order_info = MOCK_ORDERS.get(order_id)
        
        # 如果找不到订单，返回未找到状态
        if not order_info:
            logger.info(f"请求的订单ID不存在: {order_id}")
            response_body = {
                "order_id": order_id,
                "status": "未找到",
                "environment": ENVIRONMENT
            }
        else:
            # 返回找到的订单信息
            logger.info(f"找到订单信息: {order_id}")
            response_body = {
                "order_id": order_id,
                "status": order_info["status"],
                "details": order_info["details"],
                "environment": ENVIRONMENT
            }
        
        # 返回API Gateway格式的响应
        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*"
            },
            "body": json.dumps(response_body)
        }
        
    except Exception as e:
        logger.error(f"处理请求时出错: {str(e)}")
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": f"服务器内部错误: {str(e)}"})
        } 