# =============================================================================
# File: eval.py
# Created Date: 2024-10-05
# Author: liujinxun
#
# Description:
#   评估模型性能的脚本。该脚本加载验证数据集和预训练模型，
#   在验证数据上评估模型的性能，并将评估结果保存到指定的输出目录。
# =============================================================================

import numpy as np
import logging
import json
import pathlib
import tarfile

import torch
from torch.utils.data import DataLoader
from sklearn.metrics import f1_score, accuracy_score

from utils.ml_pipeline_components import load_dataset, get_model
from utils import config

# 定义评估模型的函数
def eval_model():
    """
    评估预训练的医学实体链接模型。
    该函数加载验证数据集和预训练模型，然后在验证数据上评估模型的性能。
    评估结果（准确率）将被记录并保存到指定的输出目录。
    """
    # 加载验证数据集
    dataset = load_dataset("/opt/ml/processing/val", "val")
    dataloader = DataLoader(dataset, shuffle=True, batch_size=10)
    num_labels = len(config.MEDICAL_CATEGORIES)

    logging.info("Fetching model")
    # 获取模型
    model = get_model(num_labels)

    # 加载模型参数
    model_path = "/opt/ml/processing/model/model.tar.gz"
    with tarfile.open(model_path, "r:gz") as tar:
        tar.extractall("./model")

    model.load_state_dict(torch.load("./model/model.joblib"))

    logging.info("Evaluating model")
    # 选择设备
    device = "cuda" if torch.cuda.is_available() else "cpu"
    logging.info(f"Evaluating on device: {device}")

    # 准备模型评估
    model.eval()
    model.to(device)

    # 初始化评估指标
    metrics = {
        "f1_list": [],
        "acc_list": []
    }

    # 开始评估模型
    with torch.no_grad():
        for x, y in dataloader:
            labels = y.long()
            outputs = model(x.to(device), labels=labels.to(device))
            y_pred = torch.argmax(outputs.logits.cpu(), dim=1)
            metrics["f1_list"].append(f1_score(y, y_pred, average="macro"))
            metrics["acc_list"].append(accuracy_score(y, y_pred))

    # 计算平均准确率
    accuracy = np.mean(metrics["acc_list"])
    logging.info(f"Attained accuracy: {accuracy}")
    # 构建评估报告
    report_dict = {
        "metrics": {
            "accuracy": {
                "value": accuracy,
            },
        },
    }

    # 保存评估结果
    logging.info("Saving evaluation")
    output_dir = "/opt/ml/processing/evaluation"
    pathlib.Path(output_dir).mkdir(parents=True, exist_ok=True)

    evaluation_path = f"{output_dir}/evaluation.json"
    with open(evaluation_path, "w") as f:
        f.write(json.dumps(report_dict))


if __name__ == "__main__":
    eval_model()

