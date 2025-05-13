# =============================================================================
# File: train.py
# Created Date: 2024-12-05
# Author: liujinxun
# Description:
#   本文件实现了机器学习模型的训练和测试流程。主要功能包括：
#   - 解析命令行参数
#   - 加载训练和测试数据集
#   - 定义和训练模型
#   - 测试模型性能
#   - 保存训练好的模型
# =============================================================================
import numpy as np
import os
import sys
import logging
import argparse

import torch
from torch.optim import AdamW
from torch.utils.data import DataLoader
from sklearn.metrics import f1_score, accuracy_score
from transformers import get_scheduler

import boto3
from sagemaker.session import Session
from smexperiments.tracker import Tracker


from utils.ml_pipeline_components import load_dataset, get_model
from utils import config

logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)
logger.addHandler(logging.StreamHandler(sys.stdout))


def parse_args():
    """
    解析命令行参数并返回解析后的参数。

    此函数初始化一个日志记录器以记录读取参数的过程，然后创建一个ArgumentParser对象来定义和解析命令行参数。
    参数主要包括模型超参数、数据目录路径以及模型保存目录。

    Returns:
        tuple: 包含解析后的参数对象和未解析的参数列表。
    """
    # 记录开始读取参数的日志
    logger.info("reading arguments")

    # 创建ArgumentParser对象用于解析参数
    parser = argparse.ArgumentParser()

    # 定义模型超参数，包括训练轮数、批量大小和学习率
    parser.add_argument("--epoch_count", type=int, required=True)
    parser.add_argument("--batch_size", type=int, required=True)
    parser.add_argument("--learning_rate", type=float, required=True)

    # 定义数据目录路径，默认值从环境变量获取
    parser.add_argument("--train", type=str, default=os.environ.get("SM_CHANNEL_TRAIN"))
    parser.add_argument("--test", type=str, default=os.environ.get("SM_CHANNEL_TEST"))

    # 定义模型保存目录，默认值从环境变量获取
    parser.add_argument(
        "--sm-model-dir", type=str, default=os.environ.get("SM_MODEL_DIR")
    )
    return parser.parse_known_args()


def test_model(model, test_dataloader, device):
    """
    测试模型的函数。

    此函数将模型设置为评估模式，以禁用dropout等仅在训练期间启用的功能。
    然后，它通过测试数据集对模型进行评估，计算F1分数和准确率。

    参数:
    model: 要测试的模型。
    test_dataloader: 测试数据集的加载器，用于提供数据。
    device: 设备信息，指示使用CPU还是GPU进行计算。

    返回:
    返回模型在测试数据集上的平均准确率和F1分数。
    """
    # 将模型设置为评估模式
    model.eval()

    # 初始化列表，用于存储每个批次的F1分数和准确率
    f1_list = []
    acc_list = []

    # 在测试期间禁用梯度计算，以节省内存和计算资源
    with torch.no_grad():
        # 遍历测试数据集的每个批次
        for x, y in test_dataloader:
            # 将标签转换为长整型，以适应损失函数的要求
            labels = y.long()

            # 将输入数据和标签传递给模型，进行前向传播
            outputs = model(x.to(device), labels=labels.to(device))

            # 从模型输出中获取预测的标签
            y_pred = torch.argmax(outputs.logits.cpu(), dim=1)

            # 计算并记录当前批次的F1分数
            f1_list.append(f1_score(y, y_pred, average="macro"))

            # 计算并记录当前批次的准确率
            acc_list.append(accuracy_score(y, y_pred))

    # 返回平均准确率和F1分数
    return np.mean(acc_list), np.mean(f1_list)


def train(experiment_tracker):
    """
    使用指定参数和数据集训练模型。

    参数:
    - tracker: 用于跟踪实验指标和参数的对象。
    """
    # 解析命令行参数并忽略未知参数
    args, _ = parse_args()
    # 定义记录训练进度的间隔
    log_interval = 100
    # 加载训练数据集
    logger.info("Load train data")
    train_dataset = load_dataset(args.train, "train")
    train_dataloader = DataLoader(
        train_dataset, shuffle=True, batch_size=args.batch_size
    )
    # 加载测试数据集
    logger.info("Load test data")
    test_dataset = load_dataset(args.test, "test")
    test_dataloader = DataLoader(test_dataset, shuffle=True, batch_size=args.batch_size)
    # 开始模型训练
    logger.info("Training model")
    num_labels = len(config.MEDICAL_CATEGORIES)
    model = get_model(num_labels)
    optimizer = AdamW(model.parameters(), lr=args.learning_rate)
    # 计算总训练步数
    num_epochs = args.epoch_count
    num_training_steps = num_epochs * len(train_dataloader)
    lr_scheduler = get_scheduler(
        name="linear",
        optimizer=optimizer,
        num_warmup_steps=0,
        num_training_steps=num_training_steps,
    )
    # 记录模型参数
    experiment_tracker.log_parameters(
        {
            "epoch_count": args.epoch_count,
            "batch_size": args.batch_size,
            "learning_rate": args.learning_rate,
        }
    )
    # 确定训练设备
    device = "cuda" if torch.cuda.is_available() else "cpu"
    logger.info(f"Training on device: {device}")
    # 将模型移动到训练设备
    model.to(device)
    counter = 0
    train_loss_ = 0.0
    train_acc_ = 0.0
    train_f1_ = 0.0
    # 开始轮次训练循环
    for epoch in range(num_epochs):
        model.train()
        for x, y in train_dataloader:
            labels = y.long()
            outputs = model(x.to(device), labels=labels.to(device))
            y_pred = torch.argmax(outputs.logits.cpu(), dim=1)
            f1 = f1_score(y, y_pred, average="macro")
            acc = accuracy_score(y, y_pred)

            loss = outputs.loss
            loss.backward()

            optimizer.step()
            lr_scheduler.step()
            optimizer.zero_grad()

            # 记录训练指标
            if counter % log_interval == 0:
                experiment_tracker.log_metric(
                    metric_name="training-loss",
                    value=train_loss_ / log_interval,
                    iteration_number=counter,
                )
                experiment_tracker.log_metric(
                    metric_name="training-accuracy",
                    value=train_acc_ / log_interval,
                    iteration_number=counter,
                )
                experiment_tracker.log_metric(
                    metric_name="training-f1",
                    value=train_f1_ / log_interval,
                    iteration_number=counter,
                )
                logger.info(f"Training: step {counter}")

                train_loss_ = 0.0
                train_acc_ = 0.0
                train_f1_ = 0.0

            train_loss_ += loss
            train_acc_ += acc
            train_f1_ += f1
            counter += 1

        # 测试模型性能
        test_acc, test_f1 = test_model(model, test_dataloader, device)
        logger.info(f"Test set: Average f1: {test_f1:.4f}")
        experiment_tracker.log_metric(
            metric_name="test-accuracy", value=test_acc, iteration_number=counter
        )
        experiment_tracker.log_metric(
            metric_name="test-f1", value=test_f1, iteration_number=counter
        )
    # 保存训练好的模型
    logger.info("Saving model")
    model_location = os.path.join(args.sm_model_dir, "model.joblib")
    with open(model_location, "wb") as f:
        torch.save(model.state_dict(), f)

    logger.info("Stored trained model at {}".format(model_location))


# 主程序入口
if __name__ == "__main__":
    # 初始化Sagemaker会话，指定AWS区域
    sagemaker_session = Session(boto3.session.Session(region_name="eu-west-3"))
    # 加载实验跟踪器
    with Tracker.load() as tracker:
        # 使用实验跟踪器调用训练函数
        train(tracker)