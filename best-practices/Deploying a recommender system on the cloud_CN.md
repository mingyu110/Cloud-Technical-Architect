## 摘要

本项目实践遵循一个典型用例（例如预测用户对电影的评分），端到端地介绍了在AWS上训练和部署一个推荐系统的全过程，主要聚焦于模型构建和模型部署的实践层面。

## 背景

我们去音像店租借电影观看的日子早已一去不复返。如今，用户只需点击按钮，就能访问海量的电影资源。然而，他们也面临着日益稀缺的东西——空闲时间。大多数用户不愿意花一个小时去寻找一部适合在特定时间观看的理想电影。随着实体音像店的关闭，个性化的推荐服务也随之消失了。

得益于软件和统计学，这个问题可以通过所谓的“推荐系统”来解决。**推荐系统本质上是一个机器学习系统**，它能预测用户的兴趣以及他们可能对某个项目打出的评分，旨在帮助用户发现他们可能喜欢的新产品。基本上，我们收集到的关于一个用户的数据（如电影评分）越多，我们对他们偏好的了解就越深入，从而推荐的准确性也越高。

## 推荐系统

回到音像店的时代，店员会走过来询问你的偏好，也许会问你最喜欢的电影，然后推荐一些你可能没看过的相似影片。这就是我们所说的“基于内容（content-based）”的推荐，因为它们仅仅基于物品的相似性，这一点推荐系统可以轻松解决。

另一种推荐电影的方式叫做“协同过滤（collaborative filtering）”，它根据用户的个人画像来推荐物品。想象一下这样的场景：一位店员对光顾他店铺的每一位顾客（包括他们的兴趣）都了如指掌。当顾客X到店时，店员知道顾客X的偏好与顾客Y相似，因此他/她会推荐顾客Y喜欢过但顾客X还没看过的电影。可以想见，这种方法从人类的角度是不可行的，但通过收集评分和观影信息，利用线性代数和矩阵来发现用户之间的相似性，这个问题便迎刃而解。

协同过滤系统的一种类型是基于模型的算法，它利用机器学习方法来发现这些用户相似性。在本项目中，使用了一种名为奇异值分解（Singular Value Decomposition, SVD）的算法，该算法可在Python推荐系统库[scikit-surprise](https://surprise.readthedocs.io/en/stable/matrix_factorization.html#surprise.prediction_algorithms.matrix_factorization.SVD)中找到。

如果对这些方法的数学细节感兴趣，建议阅读《推荐系统入门》([Introduction to Recommender System](https://towardsdatascience.com/intro-to-recommender-system-collaborative-filtering-64a238194a26))。

## 机器学习流水线（ML Pipeline）

部署AI服务最常见的方式之一是通过API，该API可以接收HTTP请求，并使用机器学习模型进行预测（在我们的案例中，是预测给定用户对特定电影的评分）。在本实践，将使用AWS的多种服务来构建一个机器学习流水线。

以下是用于流水线的AWS服务和外部工具列表：

- **Flask, Pandas, Scikit-Surprise** (Python库)：用于编写机器学习算法。
- **Docker**：用于将推荐算法模型打包成容器。
- **Amazon S3**：用于存储数据集和训练好的模型。
- **Amazon ECR**：用于托管自定义算法的Docker容器。
- **Amazon SageMaker**：用于训练模型和进行预测。
- **AWS Lambda函数**：用于调用SageMaker终端节点并丰富响应内容。
- **API Gateway**：用于将推荐服务的API服务发布到互联网。
- **Amazon CloudWatch**：用于事件日志记录。
- **Postman**：用于向公共API发送HTTP请求。

![img](https://miro.medium.com/v2/resize:fit:1400/1*GolOw7gbylKiDRlp3BSApg.png)

## 数据准备

第一步是收集推荐系统所需的数据。具体来说，本项目实践对电影评分信息感兴趣，这些信息将帮助算法模型发现电影和用户之间的相似性。MovieLens是最大的电影数据库之一，该数据集由GroupLens Research收集，可在此处获取：[https://grouplens.org/datasets/movielens/](https://grouplens.org/datasets/movielens/)。

将数据集上传到S3的对象存储桶（bucket）中，这些存储桶可以被其他AWS服务、自定义模型甚至容器

![img](https://miro.medium.com/v2/resize:fit:1400/1*tl-2gEcyPPWwdbh8wt4sLA.png)

## 算法容器化

尽管SageMaker提供了大量内置的机器学习算法，但在特定场景下，构建自己的自定义算法会提供更好的灵活性。

AWS希望用户的机器学习算法包含一个 *train*（训练）和一个 *serve*（服务）组件，参考这篇文章：[https://aws.amazon.com/blogs/machine-learning/train-and-host-scikit-learn-models-in-amazon-sagemaker-by-building-a-scikit-docker-container/](https://aws.amazon.com/blogs/machine-learning/train-and-host-scikit-learn-models-in-amazon-sagemaker-by-building-a-scikit-docker-container/)

- 一个SVD推荐系统可以使用Scikit-Surprise库通过网格搜索（grid search）来寻找最小化RMSE（均方根误差）指标的超参数进行训练，如下所示：

```python
#!/usr/bin/env python
# -*- coding: utf-8 -*-

# 此脚本用于训练推荐系统模型。
# 它从指定的S3路径加载训练数据，使用Grid Search寻找最佳超参数，
# 然后用最佳参数训练SVD模型，最后将训练好的模型保存到指定路径。

from __future__ import print_function

import os
import argparse
import pandas as pd

from surprise import SVD, Reader
from surprise.dataset import DatasetAutoFolds
from surprise.model_selection import GridSearchCV

if __name__ == '__main__':
    # --- 参数解析 ---
    # 使用argparse来处理命令行传入的参数
    parser = argparse.ArgumentParser()

    # --- SageMaker要求的默认参数 ---
    # 这些是SageMaker训练作业会自动传入的环境变量
    # MODEL_DIR: 训练完成后，模型需要保存到的路径
    parser.add_argument('--model-dir', type=str, default=os.environ.get('SM_MODEL_DIR'))
    # TRAIN: 训练数据的路径
    parser.add_argument('--train', type=str, default=os.environ.get('SM_CHANNEL_TRAIN'))
    
    # 解析传入的参数
    args, _ = parser.parse_known_args()

    # --- 数据加载与预处理 ---
    # 从指定的CSV文件中加载电影评分数据
    # SM_CHANNEL_TRAIN环境变量指向包含ratings.csv的目录
    ratings_df = pd.read_csv(os.path.join(args.train, 'ratings.csv'))

    # Surprise库要求特定的数据格式，因此我们定义一个Reader
    # line_format指定了列的顺序：用户ID, 物品ID, 评分
    # sep=','表示CSV文件使用逗号作为分隔符
    # rating_scale定义了评分的范围 (1-5)
    reader = Reader(line_format='user item rating', sep=',', rating_scale=(1, 5))

    # 从Pandas DataFrame加载数据到Surprise的Dataset中
    # 注意：我们跳过了CSV的表头 (skip_lines=1)
    dataset = DatasetAutoFolds.load_from_df(ratings_df[['userId', 'movieId', 'rating']], reader)
    
    # --- 模型训练：超参数调优 ---
    # 定义SVD算法的超参数网格，用于Grid Search
    # 我们将对n_epochs, lr_all, reg_all这三个参数进行调优
    param_grid = {'n_epochs': [10, 20], 'lr_all': [0.002, 0.005],
                  'reg_all': [0.4, 0.6]}
    
    # 初始化GridSearchCV对象
    # - SVD: 我们要优化的算法
    # - param_grid: 超参数搜索空间
    # - measures: 评估指标，这里使用RMSE（均方根误差）和MAE（平均绝对误差）
    # - cv=3: 3折交叉验证
    gs = GridSearchCV(SVD, param_grid, measures=['rmse', 'mae'], cv=3)

    # 在数据集上运行Grid Search
    gs.fit(dataset)

    # --- 输出最佳参数 ---
    # 打印出在验证集上达到最小RMSE的最佳参数组合
    print('最佳RMSE分数: {}'.format(gs.best_score['rmse']))
    print('最佳参数: {}'.format(gs.best_params['rmse']))

    # --- 使用最佳参数训练最终模型 ---
    # 从Grid Search的结果中获取最佳参数
    params = gs.best_params['rmse']
    # 初始化一个新的SVD模型，并设置最佳参数
    svd = SVD(n_epochs=params['n_epochs'], lr_all=params['lr_all'],
              reg_all=params['reg_all'])
    
    # 使用全部数据训练模型
    svd.fit(dataset.build_full_trainset())

    # --- 保存模型 ---
    # 将训练好的模型保存到SageMaker指定的路径
    # 模型文件名必须是'model.joblib'，这样才能被后续的serve脚本加载
    from surprise.dump import dump
    dump(os.path.join(args.model_dir, 'model.joblib'), algo=svd)

    print('模型训练完成并已保存。')
```

- 打包算法的方法是使用Docker容器，然后用户可以将这些容器推送到AWS。下面可以本实践的算法模型使用的Dockerfile：

```dockerfile
# Dockerfile for the movie recommender system

# 使用一个包含Python 3.7和Flask的官方基础镜像
# 这为我们的应用提供了一个标准的运行环境
FROM python:3.7-slim-buster

# 安装一些系统级的依赖包
# - nginx: 一个高性能的Web服务器，我们将用它作为反向代理
# - ca-certificates: 用于验证SSL/TLS连接
# - libgomp1: GNU OpenMP库，某些Python科学计算库可能需要它
RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx \
    ca-certificates \
    libgomp1

# 安装Python依赖库
# - pandas, scikit-learn, scikit-surprise: 核心的机器学习和数据处理库
# - flask, gunicorn: 用于构建和运行Web应用服务器
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 设置环境变量，这些是SageMaker容器环境的标准配置
# PYTHONUNBUFFERED: 确保Python的输出（如print语句）能直接发送到终端，方便在CloudWatch中查看日志
ENV PYTHONUNBUFFERED=TRUE
# PYTHONDONTWRITEBYTECODE: 防止Python生成.pyc文件
ENV PYTHONDONTWRITEBYTECODE=TRUE
# PATH: 将训练和服务的脚本路径添加到系统PATH中，这样SageMaker可以直接调用它们
ENV PATH="/opt/program:${PATH}"

# 将本地代码复制到Docker镜像的/opt/program目录下
# 这是我们存放所有自定义脚本和代码的地方
COPY src /opt/program

# 将Nginx的配置文件复制到镜像中
# 我们用自定义的配置来覆盖默认配置
COPY nginx.conf /etc/nginx/nginx.conf

# 设置工作目录
# 后续的CMD或ENTRYPOINT指令将在这个目录下执行
WORKDIR /opt/program
```

- 一旦Dockerfile准备就绪，就可以构建镜像并将其推送到Amazon Elastic Container Registry (ECR)。用户可以使用AWS提供的以下脚本来自动化此过程，该脚本会自动连接用户的用户名和区域，构建Docker镜像，并使其可用于SageMaker：

```bash
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
```

- 运行此脚本后，可以转到ECR并验证容器镜像已加载到注册表中。

![img](https://miro.medium.com/v2/resize:fit:1400/1*bqPuB9B_JDC0CmIgnRqPqA.png)

## 训练模型

AWS为构建机器学习模型提供了一个强大的工具，那就是SageMaker。SageMaker可以运行Docker容器，首先用电影评分数据集训练模型，然后当API被调用时，它将使用该模型根据给定的用户和电影ID进行评分推理。

使用SageMaker创建训练作业非常简单：首先指向ECR中自定义容器的路径。拥有自己的算法有助于我们通过代码中的网格搜索找到最佳模型超参数。不过，SageMaker也允许用户在训练作业配置中使用特定的值。下一步是提供通道（channels），这实际就是配置输入数据源，确保在AWS训练作业和模型算法中使用相同的通道名称。最后，用户只需指定保存模型的输出目录。

![img](https://miro.medium.com/v2/resize:fit:1400/1*ow4vU1ueOJYiYprYdbUEXg.png)


训练作业完成后，可以继续从该作业创建一个推理模型。**算法中包含一些日志以用于调试不同阶段始终是一个好的工程习惯**。训练日志可以在AWS CloudWatch服务下找到。

## 部署模型

继续使用SageMaker服务直接从模型创建一个SageMaker终端节点（Endpoint）。需要选择一个现有配置或创建一个新配置来创建配置断电。**请一定注意：只要SageMaker终端节点处于运行状态，就会被收费，所以请确保在不再需要时删除该终端节点。**

![img](https://miro.medium.com/v2/resize:fit:1400/1*e9x7DVPJQINxu515uH4bbg.png)

一旦终端节点进入服务状态（启动可能需要一些时间），部署的下一步是创建一个Lambda函数来调用终端节点，传入用户和电影，并期望收到一个预测评分。通过将此函数与终端节点关联的方法是创建一个环境变量，其值为SageMaker终端节点的名称，然后在Lambda代码中加载此变量。

使用Lambda函数的一个关键好处是以丰富SageMaker终端节点返回的HTTP响应。在本实践的场景中，除了返回预测的电影评分外，还将电影ID转换为相应的标题。这就可以通过让Lambda函数加载一个关联电影ID和标题的电影数据集（CSV文件）来实现这一点。**请注意：除了内置的Python库（os, boto3, json）之外，任何需要的Python库都必须作为[Lambda层](https://docs.aws.amazon.com/lambda/latest/dg/invocation-layers.html)添加**。可以使用以下lambda处理程序作为起点：

```python
# -*- coding: utf-8 -*-

# 此Lambda函数用于处理来自API Gateway的请求，
# 调用SageMaker终端节点进行电影评分预测，并丰富返回结果。

import os
import io
import boto3
import json
import csv
import pandas as pd

# 从环境变量中获取SageMaker终端节点的名称
# 这是将Lambda与特定SageMaker Endpoint关联的关键
ENDPOINT_NAME = os.environ['ENDPOINT_NAME']

# 初始化boto3的SageMaker运行时客户端
# 我们将使用它来调用终端节点
sagemaker_runtime = boto3.client('runtime.sagemaker')

# --- 数据加载：电影ID到标题的映射 ---
# 注意：在生产环境中，更推荐使用数据库（如DynamoDB）来存储这类映射关系，
# 而不是每次冷启动时都从S3加载CSV文件。
# 从S3加载movies.csv文件
s3 = boto3.client('s3')
# 请将存储桶名称替换为实际使用的S3存储桶
bucket = 'sagemaker-eu-west-1-123456789012' 
key = 'recommender/ml-latest-small/movies.csv'
csv_file = s3.get_object(Bucket=bucket, Key=key)
movies_df = pd.read_csv(io.BytesIO(csv_file['Body'].read()), encoding='utf8')

def lambda_handler(event, context):
    """
    Lambda函数的入口点。
    
    Args:
        event (dict): 包含请求参数的事件对象，来自API Gateway。
                      预期格式: {'body': '{"userId": "...", "movieId": "..."}'}
        context (object): 提供运行时信息的上下文对象。
    
    Returns:
        dict: 包含状态码和响应体的字典，用于返回给API Gateway。
    """
    print("接收到事件: " + json.dumps(event))
    
    # 从事件体中解析出请求数据
    # API Gateway会将POST请求的body作为字符串传递
    data = json.loads(event['body'])
    # 将数据转换为CSV格式的字符串，因为我们的SageMaker终端节点需要这种格式
    # 注意：payload的格式需要与serve脚本中predictor.py的input_fn函数相匹配
    payload = str(data['userId']) + ',' + str(data['movieId'])
    print("构造的Payload: " + payload)
    
    # --- 调用SageMaker终端节点 ---
    response = sagemaker_runtime.invoke_endpoint(
        EndpointName=ENDPOINT_NAME,
        ContentType='text/csv',  # 指定输入数据的MIME类型
        Body=payload
    )
    
    # 从终端节点的响应中解析出预测评分
    # 我们的serve脚本返回的是一个单独的预测值
    predicted_rating = json.loads(response['Body'].read().decode())
    
    # --- 丰富响应内容 ---
    # 根据movieId查找电影标题
    movie_id = int(data['movieId'])
    movie_title = movies_df[movies_df.movieId == movie_id]['title'].iloc[0]
    
    # 构造最终的JSON响应体
    enriched_response = {
        "predicted_rating": predicted_rating,
        "movie_title": movie_title
    }
    
    # --- 返回HTTP响应 ---
    # 返回给API Gateway的响应必须包含statusCode和body
    return {
        'statusCode': 200,
        'headers': {
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Origin': '*' # 允许跨域访问
        },
        'body': json.dumps(enriched_response)
    }
```

在进入下一步之前，您应该确保您的终端节点和Lambda函数工作正常。Lambda服务提供了一个简单的工具来测试函数，用户需要做的就是配置一个测试事件，在其中传入一个示例输入以验证查询的正确结果。在本实践中，可以发送以下JSON体：

```json
{
 "userId": "2",
 "movieId": "2959"
}
```

运行测试后，一旦终端节点的响应被Lambda函数丰富，就可以获得以下响应：

![img](https://miro.medium.com/v2/resize:fit:1400/1*Qme70UGjvgbAXyQLrGUdrQ.png)

机器学习部署的最后一步是创建一个可以从AWS私有虚拟云外部调用的公共API。API Gateway是能让用户从头开始构建公共REST API的服务。用户需要在该服务中做的所有事情就是创建一个资源和一个方法（在本实践是POST，因为需要在请求体中提供用户ID和电影ID），并确保选择将此REST方法与Lambda函数集成的选项。

![img](https://miro.medium.com/v2/resize:fit:1400/1*1EFujhMZU1ky0EFkjSRt4A.png)


完成以后，推荐系统现在上线了，API Gateway提供了调用我们服务所需的公共URL。

## 测试AI服务

有多种方式可以调用AI推荐服务。例如：可以使用像[*curl*](https://curl.se/docs/manpage.html)这样的命令行工具；也可以使用像Postman这样的可视化工具，。保证已将服务配置为POST方法，所以在Postman中，必须选择这种方法类型，输入从API Gateway获得的URL，并在HTTP请求中包含一个JSON体。JSON体的预期格式如下：

```json
{
 "userId": "String",
 "movieId": "String"
}
```

响应结果如下：包括电影的名称（*搏击俱乐部*）和用户的预测评分（*4.4*）。

![img](https://miro.medium.com/v2/resize:fit:1400/1*epsFfdJEKznevw5dSukDNw.png)

## 结论

本实践介绍了如何通过像AWS公有云，将一个自定义的机器学习算法投入生产，并将其应用于预测用户电影评分的推荐系统用例中。

当然，如果使用Google Cloud Platform或Microsoft Azure也可以实现类似的结果，因此用户可以选择以最高效和经济的方式满足您需求的公共云提供商。

本项目实践的代码可以参考我的GitHub：[aws_movie_recommender](https://github.com/mingyu110/Cloud-Technical-Architect/tree/main/aws_movie_recommender)
