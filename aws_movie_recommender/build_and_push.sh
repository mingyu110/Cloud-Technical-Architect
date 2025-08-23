#!/bin/bash

# 此脚本用于构建Docker镜像并将其推送到Amazon ECR（Elastic Container Registry）
#
# 使用方法:
# ./build_and_push.sh <image_name>
#
# 参数:
#   image_name: 您想要为Docker镜像指定的名称

# 检查是否提供了镜像名称参数
if [ "$#" -ne 1 ]; then
    echo "使用方法: $0 <image_name>"
    exit 1
fi

# 将第一个参数赋值给变量
IMAGE_NAME=$1

# 获取当前的AWS账户ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [ $? -ne 0 ]; then
    echo "获取AWS账户ID失败。请检查您的AWS CLI配置和权限。"
    exit 1
fi

# 获取当前的AWS区域
# 如果设置了AWS_REGION环境变量，则使用它，否则从AWS配置中获取
REGION=${AWS_REGION:-$(aws configure get region)}

# 构造ECR仓库的完整URI
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${IMAGE_NAME}"

# --- Docker 登录 ---
# 获取ECR的登录密码，并通过管道传递给docker login命令
# 这使得Docker CLI可以向您的私有ECR仓库进行身份验证
aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

# --- 创建ECR仓库 ---
# 检查ECR仓库是否已存在，如果不存在，则创建一个
aws ecr describe-repositories --repository-names "${IMAGE_NAME}" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "创建ECR仓库: ${IMAGE_NAME}"
    aws ecr create-repository --repository-name "${IMAGE_NAME}" > /dev/null
fi

# --- 构建并推送镜像 ---
# 构建Docker镜像，并使用-t参数为其打上标签（ECR URI）
echo "正在构建Docker镜像: ${ECR_URI}"
docker build -t ${ECR_URI} .

# 将构建好的镜像推送到ECR
echo "正在推送镜像到ECR..."
docker push ${ECR_URI}

echo "脚本执行完毕。镜像已成功推送至: ${ECR_URI}"
