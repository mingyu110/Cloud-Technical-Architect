import argparse
from io import StringIO
import numpy as np
import pandas as pd

import boto3
import sagemaker

from aws_profiles import UserProfiles


def upload_df(df, file_name, bucket_name, profile_name=None):
    """
    将Pandas DataFrame作为CSV文件上传到Sagemaker S3 Bucket。

    :param df: 要上传的Pandas DataFrame
    :param file_name: 上传后文件的名称
    :param bucket_name: S3桶的名称
    :param profile_name: AWS配置文件名称（可选）
    """
    session = (
        boto3.Session(profile_name=profile_name) if profile_name else boto3.Session()
    )

    if bucket_name == "sagemaker_default":
        sagemaker_session = sagemaker.Session(boto_session=session)
        bucket_name = sagemaker_session.default_bucket()

    csv_buffer = StringIO()
    df.to_csv(csv_buffer, index=False)
    s3_resource = session.resource("s3")
    s3_resource.Object(bucket_name, f"data/{file_name}").put(Body=csv_buffer.getvalue())


def split_and_upload(profile: str, bucket_name: str, csv_path: str):
    """
    加载本地数据集，拆分为训练集、测试集和验证集，并上传到S3。

    :param profile: AWS配置文件名称
    :param bucket_name: S3 Bucket的名称
    :param csv_path: 本地CSV文件的路径
    """
    # 加载本地数据集
    df = pd.read_csv(csv_path)

    # 删除空行
    df = df[df["transcription"].notna()]

    # 打乱数据集
    df = df.sample(frac=1, random_state=42)

    # 将数据集拆分为70%训练集、15%测试集和15%验证集
    train, test, val = np.split(df, [int(0.7 * len(df)), int(0.85 * len(df))])

    # 将NumPy数组转换为Pandas DataFrame
    train = pd.DataFrame(train, columns=df.columns)
    test = pd.DataFrame(test, columns=df.columns)
    val = pd.DataFrame(val, columns=df.columns)

    # 重置索引
    train.reset_index(drop=True, inplace=True)
    test.reset_index(drop=True, inplace=True)
    val.reset_index(drop=True, inplace=True)

    # 将数据保存到S3
    upload_df(train, "train.csv", bucket_name, profile)
    upload_df(test, "test.csv", bucket_name, profile)
    upload_df(val, "val.csv", bucket_name, profile)


if __name__ == "__main__":
    userProfiles = UserProfiles()
    profiles = userProfiles.list_profiles()

    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", type=str, default=None, choices=profiles, help="AWS配置文件名称")
    parser.add_argument("--bucket-name", type=str, default="sagemaker_default", help="S3桶的名称")
    parser.add_argument("--csv-path", type=str, default="data/mtsamples.csv", help="本地CSV文件的路径")

    args = parser.parse_args()

    split_and_upload(args.profile, args.bucket_name, args.csv_path)
