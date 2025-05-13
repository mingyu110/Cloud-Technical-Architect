import json
import boto3
import os
import random
import uuid
from datetime import datetime, timezone
import logging

# 配置日志
logger = logging.getLogger()
logger.setLevel(logging.INFO)

kinesis_client = boto3.client('kinesis')
STREAM_NAME = os.environ.get('KINESIS_STREAM_NAME', 'vehicle-metrics-stream')

def generate_vehicle_data(vehicle_id):
    data = {
        'vehicle_id': vehicle_id,
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'location': {
            'latitude': round(random.uniform(39.9, 40.1), 6),
            'longitude': round(random.uniform(116.3, 116.5), 6)
        },
        'speed': round(random.uniform(0, 120), 2),
        'engine_temperature': round(random.uniform(80, 120), 2),
        'fuel_level': round(random.uniform(0, 100), 2),
        'battery_voltage': round(random.uniform(11.5, 14.5), 2),
        'tire_pressure': {
            'front_left': round(random.uniform(30, 35), 2),
            'front_right': round(random.uniform(30, 35), 2),
            'rear_left': round(random.uniform(30, 35), 2),
            'rear_right': round(random.uniform(30, 35), 2)
        }
    }
    logger.info(f"Generated data for vehicle {vehicle_id}: {json.dumps(data)}")
    return data

def lambda_handler(event, context):
    logger.info(f"Lambda function started. Event: {json.dumps(event)}")
    logger.info(f"Using Kinesis stream: {STREAM_NAME}")
    
    try:
        num_vehicles = int(os.environ.get('NUM_VEHICLES', 10))
        logger.info(f"Will generate data for {num_vehicles} vehicles")
        
        # 增加生成的车辆数量到50辆，提高数据量
        num_vehicles = max(num_vehicles, 50)
        
        for i in range(num_vehicles):
            vehicle_id = str(uuid.uuid4())
            data = generate_vehicle_data(vehicle_id)
            
            logger.info(f"Sending data to Kinesis for vehicle {vehicle_id}")
            try:
                response = kinesis_client.put_record(
                    StreamName=STREAM_NAME,
                    Data=json.dumps(data),
                    PartitionKey=vehicle_id
                )
                logger.info(f"Successfully sent data to Kinesis. Response: {json.dumps(response)}")
            except Exception as e:
                logger.error(f"Error sending data to Kinesis for vehicle {vehicle_id}: {str(e)}")
                raise
                
        logger.info(f"Successfully generated and sent data for {num_vehicles} vehicles")
        return {
            'statusCode': 200,
            'body': f'Successfully generated {num_vehicles} vehicle records'
        }
    except Exception as e:
        logger.error(f"Error in lambda_handler: {str(e)}")
        raise 