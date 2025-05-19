import json

def lambda_handler(event, context):
    """简化版订单状态模拟API"""
    
    # 固定返回订单12345的状态
    response_body = {
        'order_id': '12345',
        'status': '已发货',
        'environment': 'dev'
    }
    
    # 返回API Gateway格式的响应
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(response_body)
    } 