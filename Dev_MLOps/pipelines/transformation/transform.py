import pandas as pd
import boto3
import os
from pipelines.utils.preprocessing import preprocess

def load_from_s3(bucket, key):
    s3 = boto3.client('s3')
    s3.download_file(bucket, key, '/tmp/input.csv')
    return pd.read_csv('/tmp/input.csv')

def save_to_s3(df, bucket, key):
    df.to_csv('/tmp/processed.csv', index=False)
    s3 = boto3.client('s3')
    s3.upload_file('/tmp/processed.csv', bucket, key)

if __name__ == "__main__":
    bucket = os.getenv("S3_BUCKET")
    raw_df = load_from_s3(bucket, "raw/timeseries.csv")
    processed_df = preprocess(raw_df)
    save_to_s3(processed_df, bucket, "processed/timeseries.csv")
