# approve.py
#
# =============================================================================
# File: approve.py
# Created Date: 2024-10-05
# Author: liujinxun
#
# Description:
#   本文件包含用于批准 SageMaker 模型的函数。通过与 AWS SageMaker 服务交互，
#   将指定的模型包状态更新为已批准。
# =============================================================================


import os
import sys
import logging

# 导入 AWS SDK 的 boto3 模块
import boto3

# 初始化日志记录器
logger = logging.getLogger(__name__)
# 设置日志级别为 DEBUG
logger.setLevel(logging.DEBUG)
# 添加标准输出处理器
logger.addHandler(logging.StreamHandler(sys.stdout))

# 定义批准模型的函数
def approve_model():
    # 记录函数调用信息
    logger.info("Approve model")
    # 创建 SageMaker 客户端，指定区域为 eu-west-3
    sm_client = boto3.Session(region_name="eu-west-3").client("sagemaker")
    # 从环境变量中获取模型包组的 ARN
    model_package_group_arn = os.environ.get("model_package_group_arn")
    # 从环境变量中获取模型包版本
    model_package_version = os.environ.get("model_package_version")

    # 记录模型包组的 ARN
    logger.info(f"model_package_group_arn: {model_package_group_arn}")
    # 记录模型包版本
    logger.info(f"model_package_version: {model_package_version}")

    # 构建完整的模型包 ARN
    model_package_arn = model_package_group_arn + "/" + model_package_version

    # 记录完整的模型包 ARN
    logger.info(f"model_package_arn: {model_package_arn}")

    # 更新模型状态为已批准
    model_package_update_input_dict = {
        "ModelPackageArn": model_package_arn,
        "ModelApprovalStatus": "Approved",
    }
    # 调用 SageMaker 客户端更新模型包状态
    sm_client.update_model_package(**model_package_update_input_dict)

# 主程序入口
if __name__ == "__main__":
    # 调用批准模型的函数
    approve_model()
