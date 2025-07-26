import pandas as pd

def preprocess(df):
    df = df.dropna()
    df["target"] = df["value"].shift(-1)
    df = df.dropna()
    return df
