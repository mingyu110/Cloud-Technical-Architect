import pandas as pd
import requests
import boto3
import os

def download_data():
    url = "https://example.com/timeseries.csv"
    df = pd.read_csv(url)
    return df

def upload_to_s3(df, bucket, key):
    s3 = boto3.client('s3')
    df.to_csv('/tmp/data.csv', index=False)
    s3.upload_file('/tmp/data.csv', bucket, key)

if __name__ == "__main__":
    df = download_data()
    upload_to_s3(df, os.getenv("S3_BUCKET"), "raw/timeseries.csv")
