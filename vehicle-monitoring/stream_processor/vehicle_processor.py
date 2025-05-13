import json
import boto3
import time
from datetime import datetime, timedelta

class VehicleDataProcessor:
    def __init__(self):
        self.kinesis_client = boto3.client('kinesis')
        self.timestream_client = boto3.client('timestream-write')
        self.stream_name = 'vehicle-metrics-stream'
        self.database_name = 'vehicle_metrics'
        self.table_name = 'vehicle_data'
        
    def process_record(self, record):
        """处理单条记录"""
        try:
            data = json.loads(record['Data'])
            
            # 提取关键指标
            metrics = {
                'speed': data['speed'],
                'engine_temperature': data['engine_temperature'],
                'fuel_level': data['fuel_level'],
                'battery_voltage': data['battery_voltage']
            }
            
            # 计算轮胎压力平均值
            tire_pressures = data['tire_pressure'].values()
            metrics['avg_tire_pressure'] = sum(tire_pressures) / len(tire_pressures)
            
            # 添加告警逻辑
            alerts = []
            if metrics['speed'] > 100:
                alerts.append('HIGH_SPEED')
            if metrics['engine_temperature'] > 110:
                alerts.append('HIGH_TEMPERATURE')
            if metrics['fuel_level'] < 20:
                alerts.append('LOW_FUEL')
            if metrics['battery_voltage'] < 12:
                alerts.append('LOW_BATTERY')
            
            # 写入Timestream
            self.write_to_timestream(data['vehicle_id'], metrics, alerts)
            
            return {
                'vehicle_id': data['vehicle_id'],
                'metrics': metrics,
                'alerts': alerts,
                'timestamp': data['timestamp']
            }
            
        except Exception as e:
            print(f"Error processing record: {str(e)}")
            return None
    
    def write_to_timestream(self, vehicle_id, metrics, alerts):
        """写入数据到Timestream"""
        try:
            current_time = int(time.time() * 1000)  # 毫秒时间戳
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
                    'Time': str(current_time)
                })
            # 写入告警信息
            if alerts:
                records.append({
                    'Dimensions': [
                        {'Name': 'vehicle_id', 'Value': vehicle_id},
                        {'Name': 'alert_type', 'Value': ','.join(alerts)}
                    ],
                    'MeasureName': 'alert_count',
                    'MeasureValue': str(len(alerts)),
                    'MeasureValueType': 'BIGINT',
                    'Time': str(current_time)
                })
            response = self.timestream_client.write_records(
                DatabaseName=self.database_name,
                TableName=self.table_name,
                Records=records
            )
            print(f"Write to Timestream response: {response}")
        except Exception as e:
            print(f"Error writing to Timestream: {str(e)}")
    
    def run(self):
        """运行流处理器"""
        shard_iterator = self.kinesis_client.get_shard_iterator(
            StreamName=self.stream_name,
            ShardId='shardId-000000000000',
            ShardIteratorType='LATEST'
        )['ShardIterator']
        
        while True:
            try:
                response = self.kinesis_client.get_records(
                    ShardIterator=shard_iterator,
                    Limit=100
                )
                records = response['Records']
                print(f"Fetched {len(records)} records from Kinesis.")
                for record in records:
                    # 打印原始内容（截断显示前200字符）
                    print(f"Raw record: {record['Data'][:200]}")
                    result = self.process_record(record)
                    if result:
                        print(f"Processed data for vehicle {result['vehicle_id']}")
                        if result['alerts']:
                            print(f"Alerts: {result['alerts']}")
                shard_iterator = response['NextShardIterator']
                time.sleep(1)
            except Exception as e:
                print(f"Error in stream processing: {str(e)}")
                time.sleep(1)

if __name__ == "__main__":
    processor = VehicleDataProcessor()
    processor.run() 