# 文件: src/preprocess.py
# 作者: liujinxun
# 日期: 2024-12-05
# 描述: 该文件包含用于医疗文本分类的数据预处理功能。主要包括以下步骤：
#       1. 读取训练集、测试集和验证集的 CSV 文件。
#       2. 使用自定义的分词器对文本数据进行分词。
#       3. 使用编码器对标签进行编码。
#       4. 将处理后的数据保存为 Numpy 数组文件。
#
# 依赖库:
#   - numpy (np): 数值计算库。
#   - pandas (pd): 数据处理库。
#   - os: 操作系统接口。
#   - logging: 日志记录。
#   - utils.ml_pipeline_components: 自定义的分词器和编码器组件。

import numpy as np
import pandas as pd
import os
import logging

from utils.ml_pipeline_components import MyTokenizer, Encoder


def preprocess():
    # 记录日志：获取数据集
    logging.info("fetching dataset")
    # 读取训练集、测试集和验证集
    df_train = pd.read_csv(os.path.join("/opt/ml/processing/input/train", "train.csv"))
    df_test = pd.read_csv(os.path.join("/opt/ml/processing/input/test", "test.csv"))
    df_val = pd.read_csv(os.path.join("/opt/ml/processing/input/val", "val.csv"))

    # 记录日志：对数据集进行分词
    logging.info("tokenizing dataset")
    # 初始化分词器
    tokenizer = MyTokenizer()
    # 对训练集、测试集和验证集的文本进行分词
    x_train = [tokenizer.tokenize(v) for v in df_train.transcription.values]
    x_test = [tokenizer.tokenize(v) for v in df_test.transcription.values]
    x_val = [tokenizer.tokenize(v) for v in df_val.transcription.values]

    # 初始化编码器
    encoder = Encoder(df_train, df_test, df_val)
    # 对训练集、测试集和验证集的标签进行编码
    y_train = [encoder.encode(c) for c in df_train.medical_specialty.values]
    y_test = [encoder.encode(c) for c in df_test.medical_specialty.values]
    y_val = [encoder.encode(c) for c in df_val.medical_specialty.values]

    # 记录日志：保存数据集
    logging.info("saving dataset")

    # 保存训练集
    np.save(os.path.join("/opt/ml/processing/output/train", "x_train.npy"), x_train)
    np.save(os.path.join("/opt/ml/processing/output/train", "y_train.npy"), y_train)

    # 保存测试集
    np.save(os.path.join("/opt/ml/processing/output/test", "x_test.npy"), x_test)
    np.save(os.path.join("/opt/ml/processing/output/test", "y_test.npy"), y_test)

    # 保存验证集
    np.save(os.path.join("/opt/ml/processing/output/val", "x_val.npy"), x_val)
    np.save(os.path.join("/opt/ml/processing/output/val", "y_val.npy"), y_val)


if __name__ == "__main__":
    # 如果脚本直接运行，则调用预处理函数
    preprocess()

