# -*- coding: utf-8 -*-

# 此Lambda函数用于处理来自API Gateway的请求，
# 调用SageMaker终端节点进行电影评分预测，并丰富返回结果。

import os
import io
import boto3
import json
import csv
import pandas as pd

# 从环境变量中获取SageMaker终端节点的名称
# 这是将Lambda与特定SageMaker Endpoint关联的关键
ENDPOINT_NAME = os.environ['ENDPOINT_NAME']

# 初始化boto3的SageMaker运行时客户端
# 我们将使用它来调用终端节点
sagemaker_runtime = boto3.client('runtime.sagemaker')

# --- 数据加载：电影ID到标题的映射 ---
# 注意：在生产环境中，更推荐使用数据库（如DynamoDB）来存储这类映射关系，
# 而不是每次冷启动时都从S3加载CSV文件。
# 从S3加载movies.csv文件
s3 = boto3.client('s3')
# 请将存储桶名称替换为实际使用的S3存储桶
bucket = 'sagemaker-eu-west-1-123456789012' 
key = 'recommender/ml-latest-small/movies.csv'
csv_file = s3.get_object(Bucket=bucket, Key=key)
movies_df = pd.read_csv(io.BytesIO(csv_file['Body'].read()), encoding='utf8')

def lambda_handler(event, context):
    """
    Lambda函数的入口点。
    
    Args:
        event (dict): 包含请求参数的事件对象，来自API Gateway。
                      预期格式: {'body': '{"userId": "...", "movieId": "..."}'}
        context (object): 提供运行时信息的上下文对象。
    
    Returns:
        dict: 包含状态码和响应体的字典，用于返回给API Gateway。
    """
    print("接收到事件: " + json.dumps(event))
    
    # 从事件体中解析出请求数据
    # API Gateway会将POST请求的body作为字符串传递
    data = json.loads(event['body'])
    # 将数据转换为CSV格式的字符串，因为我们的SageMaker终端节点需要这种格式
    # 注意：payload的格式需要与serve脚本中predictor.py的input_fn函数相匹配
    payload = str(data['userId']) + ',' + str(data['movieId'])
    print("构造的Payload: " + payload)
    
    # --- 调用SageMaker终端节点 ---
    response = sagemaker_runtime.invoke_endpoint(
        EndpointName=ENDPOINT_NAME,
        ContentType='text/csv',  # 指定输入数据的MIME类型
        Body=payload
    )
    
    # 从终端节点的响应中解析出预测评分
    # 我们的serve脚本返回的是一个单独的预测值
    predicted_rating = json.loads(response['Body'].read().decode())
    
    # --- 丰富响应内容 ---
    # 根据movieId查找电影标题
    movie_id = int(data['movieId'])
    movie_title = movies_df[movies_df.movieId == movie_id]['title'].iloc[0]
    
    # 构造最终的JSON响应体
    enriched_response = {
        "predicted_rating": predicted_rating,
        "movie_title": movie_title
    }
    
    # --- 返回HTTP响应 ---
    # 返回给API Gateway的响应必须包含statusCode和body
    return {
        'statusCode': 200,
        'headers': {
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Origin': '*' # 允许跨域访问
        },
        'body': json.dumps(enriched_response)
    }