import json
import boto3
import os
import base64
import logging
from datetime import datetime

# 配置日志
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# 初始化Timestream客户端
timestream_client = boto3.client('timestream-write')
DATABASE_NAME = os.environ.get('TIMESTREAM_DATABASE', 'vehicle_metrics')
TABLE_NAME = os.environ.get('TIMESTREAM_TABLE', 'vehicle_data')

def process_record(data):
    """处理单条车辆数据记录，计算指标并生成警报"""
    try:
        metrics = {
            'speed': data['speed'],
            'engine_temperature': data['engine_temperature'],
            'fuel_level': data['fuel_level'],
            'battery_voltage': data['battery_voltage']
        }
        tire_pressures = data['tire_pressure'].values()
        metrics['avg_tire_pressure'] = sum(tire_pressures) / len(tire_pressures)
        alerts = []
        if metrics['speed'] > 100:
            alerts.append('HIGH_SPEED')
        if metrics['engine_temperature'] > 110:
            alerts.append('HIGH_TEMPERATURE')
        if metrics['fuel_level'] < 20:
            alerts.append('LOW_FUEL')
        if metrics['battery_voltage'] < 12:
            alerts.append('LOW_BATTERY')
        return metrics, alerts
    except KeyError as e:
        logger.error(f"Missing key in vehicle data: {e}")
        raise
    except Exception as e:
        logger.error(f"Error processing record: {e}")
        raise

def lambda_handler(event, context):
    """处理来自Kinesis的事件流数据"""
    logger.info(f"Processing batch of {len(event.get('Records', []))} records")
    
    processed_count = 0
    error_count = 0
    
    for record in event.get('Records', []):
        try:
            # 解码Kinesis数据
            payload = base64.b64decode(record['kinesis']['data'])
            data = json.loads(payload)
            vehicle_id = data.get('vehicle_id', 'unknown')
            
            logger.info(f"Processing data for vehicle: {vehicle_id}")
            
            # 处理记录
            metrics, alerts = process_record(data)
            current_time = str(int(datetime.now().timestamp() * 1000))
            
            # 准备Timestream记录
            records = []
            for metric_name, value in metrics.items():
                records.append({
                    'Dimensions': [
                        {'Name': 'vehicle_id', 'Value': vehicle_id},
                        {'Name': 'metric_name', 'Value': metric_name}
                    ],
                    'MeasureName': 'value',
                    'MeasureValue': str(value),
                    'MeasureValueType': 'DOUBLE',
                    'Time': current_time
                })
            
            if alerts:
                alert_str = ','.join(alerts)
                logger.info(f"Alerts detected for vehicle {vehicle_id}: {alert_str}")
                records.append({
                    'Dimensions': [
                        {'Name': 'vehicle_id', 'Value': vehicle_id},
                        {'Name': 'alert_type', 'Value': alert_str}
                    ],
                    'MeasureName': 'alert_count',
                    'MeasureValue': str(len(alerts)),
                    'MeasureValueType': 'BIGINT',
                    'Time': current_time
                })
            
            # 写入Timestream
            timestream_client.write_records(
                DatabaseName=DATABASE_NAME,
                TableName=TABLE_NAME,
                Records=records
            )
            
            processed_count += 1
            
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON in Kinesis record: {e}")
            error_count += 1
        except Exception as e:
            logger.error(f"Error processing Kinesis record: {e}")
            error_count += 1
    
    logger.info(f"Processing complete. Processed: {processed_count}, Errors: {error_count}")
    return {
        'statusCode': 200, 
        'body': json.dumps({
            'processed': processed_count,
            'errors': error_count
        })
    } 