# ===============================================================
# 文件: src/model.py
# 作者: liujinxun
# 日期: 2024-12-05
# 描述: 该文件包含用于医疗文本分类的模型预测功能。主要包括四个主要函数：
#       - predict_fn: 处理输入数据并返回预测结果。
#       - input_fn: 解析输入数据负载。
#       - output_fn: 格式化预测输出。
#       - model_fn: 反序列化/加载训练好的模型。
#
# 依赖库:
#   - os: 操作系统接口。
#   - sys: 系统特定参数和函数。
#   - json: JSON 数据解析。
#   - logging: 日志记录。
#   - pandas (pd): 数据处理库。
#   - io: 文件操作。
#   - tqdm: 进度条显示。
#   - torch: PyTorch 深度学习框架。
#   - torch.utils.data.DataLoader: 数据加载器。
#   - utils.ml_pipeline_components: 自定义的模型和数据处理组件。
#   - utils.config: 配置文件。
# ==============================================================
import os
import sys
import json
import logging
import pandas as pd
from io import StringIO
from tqdm import tqdm

import torch
from torch.utils.data import DataLoader

from utils.ml_pipeline_components import get_model, MyTokenizer, MyDataset
from utils import config

# 初始化日志记录器
logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)
logger.addHandler(logging.StreamHandler(sys.stdout))


def predict_fn(input_data, model):
    """
    处理输入数据并返回预测结果。

    参数:
    - input_data: 预测用的输入数据。
    - model: 用于预测的模型。

    返回:
    - 预测结果列表。
    """
    logger.info("predict_fn")

    # 确定设备
    device = "cuda" if torch.cuda.is_available() else "cpu"
    logger.info(f"设备: {device}")

    # 将模型设置为评估模式并移动到设备
    model.eval()
    model.to(device)
    tok = MyTokenizer()

    # 对输入数据进行分词
    tokenized_input = tok.tokenizer(
        input_data, padding="max_length", return_tensors="pt", truncation=True
    )

    # 创建数据集和数据加载器
    dataset = MyDataset(tokenized_input.input_ids, tokenized_input.attention_mask)
    dataloader = DataLoader(dataset, shuffle=False, batch_size=10)

    output = []
    # 执行预测
    for x, _ in tqdm(dataloader):
        outs = model(x.to(device))
        output += torch.argmax(outs.logits.cpu(), dim=1)

    # 将输出转换为医疗类别标签
    return [config.MEDICAL_CATEGORIES[i.item()] for i in output]


def input_fn(input_data, content_type):
    """
    解析输入数据负载。

    参数:
    - input_data: 要处理的输入数据。
    - content_type: 输入数据的内容类型。

    返回:
    - 处理后的输入数据。
    """
    logger.info("input_fn")
    if content_type == "application/json":
        input_dict = json.loads(input_data)
        return input_dict["instances"]
    elif content_type == "text/csv":
        df = pd.read_csv(StringIO(input_data), sep=",")
        inputs = df["transcription"].tolist()
        return inputs
    else:
        raise ValueError("{} not supported by script!".format(content_type))


def output_fn(prediction, accept):
    """
    格式化预测输出。

    参数:
    - prediction: 预测结果。
    - accept: 输出的内容类型。

    返回:
    - 格式化的预测输出。
    """
    logger.info("output_fn")
    if accept == "application/json":
        return {"prediction": prediction}
    elif accept == "text/csv":
        return prediction
    else:
        raise RuntimeError(
            "{} accept type is not supported by this script.".format(accept)
        )


def model_fn(model_dir):
    """
    反序列化/加载训练好的模型。

    参数:
    - model_dir: 存储模型的目录。

    返回:
    - 加载的模型。
    """
    logger.info("model_fn")
    model = get_model(num_labels=len(config.MEDICAL_CATEGORIES))
    device = "cuda" if torch.cuda.is_available() else "cpu"

    # 加载模型状态字典
    model.load_state_dict(
        torch.load(
            os.path.join(model_dir, "model.joblib"), map_location=torch.device(device)
        )
    )
    return model
