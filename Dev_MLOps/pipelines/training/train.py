import pandas as pd
import xgboost as xgb
import mlflow
import os
import boto3

def load_data(bucket, key):
    s3 = boto3.client('s3')
    s3.download_file(bucket, key, '/tmp/data.csv')
    return pd.read_csv('/tmp/data.csv')

if __name__ == "__main__":
    mlflow.set_tracking_uri(os.getenv("MLFLOW_TRACKING_URI"))
    mlflow.set_experiment("time-series-forecasting")

    with mlflow.start_run():
        df = load_data(os.getenv("S3_BUCKET"), "processed/timeseries.csv")
        
        # Dummy split
        X, y = df.drop(columns="target"), df["target"]
        model = xgb.XGBRegressor()
        model.fit(X, y)

        mlflow.xgboost.log_model(model, "model")
        mlflow.log_params(model.get_params())
