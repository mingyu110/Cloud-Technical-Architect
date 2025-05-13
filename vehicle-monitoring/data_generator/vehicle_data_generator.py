import json
import random
import time
import boto3
from datetime import datetime
import uuid

class VehicleDataGenerator:
    def __init__(self):
        self.kinesis_client = boto3.client('kinesis')
        self.stream_name = 'vehicle-metrics-stream'
        
    def generate_vehicle_data(self, vehicle_id):
        """生成单个车辆的模拟数据"""
        return {
            'vehicle_id': vehicle_id,
            'timestamp': datetime.utcnow().isoformat(),
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
    
    def send_to_kinesis(self, data):
        """发送数据到Kinesis流"""
        try:
            response = self.kinesis_client.put_record(
                StreamName=self.stream_name,
                Data=json.dumps(data),
                PartitionKey=data['vehicle_id']
            )
            print("PutRecord response:", response)
        except Exception as e:
            print(f"Error sending data to Kinesis: {str(e)}")
    
    def run(self, num_vehicles=200, interval=0.05):
        """运行数据生成器"""
        vehicle_ids = [str(uuid.uuid4()) for _ in range(num_vehicles)]
        
        while True:
            for vehicle_id in vehicle_ids:
                data = self.generate_vehicle_data(vehicle_id)
                self.send_to_kinesis(data)
                print(f"Generated data for vehicle {vehicle_id}")
            time.sleep(interval)

if __name__ == "__main__":
    generator = VehicleDataGenerator()
    generator.run() 