import os
import pandas as pd
import xgboost as xgb
import mlflow.pyfunc
from flask import Flask, request, jsonify

app = Flask(__name__)
model = mlflow.pyfunc.load_model(os.getenv("MODEL_URI", "models:/time-series-forecasting/Production"))

@app.route("/predict", methods=["POST"])
def predict():
    input_data = pd.DataFrame(request.json)
    prediction = model.predict(input_data)
    return jsonify(prediction.tolist())

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
