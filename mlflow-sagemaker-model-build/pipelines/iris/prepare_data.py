import argparse
import logging
import pandas as pd
from sklearn.datasets import load_iris
from sklearn.model_selection import train_test_split

logger = logging.getLogger()
logger.setLevel(logging.INFO)
logger.addHandler(logging.StreamHandler())


if __name__ == "__main__":
    logger.info("Running data preparation...")
    
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=str, default="")
    args, _ = parser.parse_known_args()

    # Load the Iris dataset from sk-learn
    data = load_iris()

    X_train, X_test, y_train, y_test = train_test_split(data.data, data.target, test_size=0.25, random_state=42)

    trainX = pd.DataFrame(X_train, columns=data.feature_names)
    trainX['target'] = y_train

    testX = pd.DataFrame(X_test, columns=data.feature_names)
    testX['target'] = y_test

    logger.info(trainX.head(10))
    
    # save train and test CSV files
    logger.info(f"Writing data to {args.output_dir}")
    trainX.to_csv(f'{args.output_dir}/iris_train.csv', index=False)
    testX.to_csv(f'{args.output_dir}/iris_test.csv', index=False)
