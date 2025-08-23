# AWS云上推荐系统部署实践

## 1. 项目简介

本项目是一个端到端的机器学习实践，旨在演示如何在AWS上训练、部署并提供一个电影推荐系统服务。项目采用协同过滤算法，根据用户历史评分数据，预测用户对特定电影的评分，并通过一个公开的API接口提供服务。

整个流程覆盖了数据准备、算法容器化、模型训练、服务部署和API发布等关键环节，是学习和实践MLOps的典型案例。

## 2. 技术架构

本项目的核心是一个基于AWS各项服务的解耦、可扩展的机器学习流水线（ML Pipeline）。

**架构图:**

![架构图](https://miro.medium.com/v2/resize:fit:1400/1*GolOw7gbylKiDRlp3BSApg.png)

**核心流程说明:**

1.  **数据存储 (S3)**: 原始的电影评分数据集 (`ratings.csv`) 存储在Amazon S3存储桶中，作为训练任务的数据源。
2.  **算法容器化 (Docker & ECR)**: 我们没有使用SageMaker的内置算法，而是将自定义的训练和推理代码（基于`scikit-surprise`）打包成一个Docker镜像，并推送至Amazon ECR (弹性容器注册表)进行托管。
3.  **模型训练 (SageMaker)**: 创建一个SageMaker训练作业，该作业从ECR拉取我们的自定义镜像，从S3读取训练数据，执行训练脚本 (`train`)，并将训练好的模型产物（`model.joblib`）存回S3。
4.  **模型部署 (SageMaker)**: 基于训练产物，创建一个SageMaker实时终端节点（Endpoint）。该终端节点在后台运行我们的容器，并加载模型用于实时推理（通过`serve`脚本）。
5.  **业务逻辑与丰富化 (Lambda)**: 创建一个AWS Lambda函数，它作为后端业务逻辑层。它接收API请求，调用SageMaker终端节点获取预测评分，并进一步调用S3上的`movies.csv`文件，将电影ID转换为用户可读的电影标题，从而丰富响应内容。
6.  **API发布 (API Gateway)**: 使用Amazon API Gateway创建一个RESTful API（POST方法），并将其与Lambda函数集成。API Gateway负责处理HTTP请求、安全认证，并将请求路由到Lambda函数，最终将结果返回给客户端。
7.  **监控与日志 (CloudWatch)**: 所有的服务（SageMaker, Lambda等）的日志都会被发送到Amazon CloudWatch，便于监控和调试。

## 3. 环境准备

在开始之前，请确保您已准备好以下环境：

- **AWS账户**: 一个有效的AWS账户，并拥有创建S3、ECR、SageMaker、Lambda等服务的IAM权限。
- **AWS CLI**: 在本地安装并配置好AWS命令行工具，确保您的Access Key、Secret Key和默认Region已配置正确。
- **Docker**: 本地已安装并正在运行Docker Desktop。
- **Python 3.7+**: 本地已安装Python环境。
- **项目代码**: 已将本仓库克隆到本地。

## 4. 部署步骤

请严格按照以下步骤执行：

### 第1步：准备数据

1.  创建一个S3存储桶（例如 `your-name-sagemaker-bucket`）。
2.  在存储桶内，创建一个用于存放原始数据的目录（例如 `recommender/ml-latest-small/`）。
3.  将项目`data`目录下的 `ratings.csv` 和 `movies.csv` 文件上传到您刚刚创建的S3目录中。

### 第2步：构建和推送Docker镜像

1.  打开终端，进入项目根目录 (`aws_movie_recommender`)。
2.  确保 `build_and_push.sh` 脚本有执行权限：
    ```bash
    chmod +x build_and_push.sh
    ```
3.  执行脚本，并为您的镜像命名（例如 `movie-recommender`）：
    ```bash
    ./build_and_push.sh movie-recommender
    ```
4.  脚本会自动完成登录ECR、创建仓库、构建镜像和推送镜像的全过程。完成后，请前往AWS控制台的ECR服务页面，确认镜像已成功上传。

### 第3步：训练模型

1.  前往AWS控制台的 **Amazon SageMaker** 服务页面。
2.  在左侧导航栏选择 **训练 -> 训练作业**，点击“创建训练作业”。
3.  **算法来源**: 选择“自定义算法”，然后在“算法来源”下选择“ECR中的算法”，并指定您在上一步中推送的容器镜像URI。
4.  **输入数据配置**: 创建一个名为 `train` 的通道，将其指向您在S3中存放 `ratings.csv` 的路径 (例如 `s3://your-bucket/recommender/ml-latest-small/`)。
5.  **输出数据配置**: 指定一个S3路径，用于存放训练完成后生成的模型文件 (例如 `s3://your-bucket/recommender/output/`)。
6.  **资源配置**: 选择一个合适的实例类型（例如 `ml.m5.large`）。
7.  点击“创建训练作业”并等待其完成。

### 第4步：部署模型终端节点

1.  训练作业成功完成后，在训练作业详情页面，点击“创建模型”。
2.  在创建模型的页面，保持默认配置，它会自动关联正确的镜像和模型数据路径。点击“创建模型”。
3.  模型创建成功后，前往 **推理 -> 终端节点** 页面，点击“创建终端节点”。
4.  为终端节点命名，并选择上一步创建的模型。点击“创建终端节点配置”，然后创建终端节点。
5.  等待终端节点的状态变为 **InService**。此过程可能需要5-10分钟。

### 第5步：创建并配置Lambda函数

1.  前往AWS控制台的 **AWS Lambda** 服务页面。
2.  创建一个新的函数，选择“从头开始创作”，使用Python 3.8或更高版本的运行时。
3.  **代码**: 将 `src/lambda_function.py` 文件中的代码粘贴到Lambda的代码编辑器中。
    - **重要**: 修改代码中S3存储桶的名称，将其替换为您自己的存储桶名称。
4.  **环境变量**: 创建一个名为 `ENDPOINT_NAME` 的环境变量，其值为您在上一步中创建的SageMaker终端节点的名称。
5.  **权限**: 确保Lambda函数的执行角色（IAM Role）拥有调用SageMaker终端节点 (`sagemaker:InvokeEndpoint`) 和从S3读取对象 (`s3:GetObject`) 的权限。
6.  **层 (Layer)**: `lambda_function.py` 依赖 `pandas` 库，而Lambda运行时默认不包含它。您需要创建一个包含Pandas库的Lambda层，并将其附加到此函数。

### 第6步：创建API Gateway

1.  前往AWS控制台的 **API Gateway** 服务页面。
2.  创建一个新的 **REST API**。
3.  在“资源”下，创建一个新的资源（例如 `/predict`），并为该资源创建一个 **POST** 方法。
4.  在POST方法的设置中，选择“Lambda 函数”作为集成类型，并选择您刚刚创建的Lambda函数。
5.  部署API到一个新的阶段（例如 `v1`）。
6.  部署完成后，您将获得一个“调用URL”，这就是您的公共API入口。

### 第7步：测试服务

使用Postman或curl等工具，向您获得的API调用URL发送一个POST请求。

- **URL**: `[你的API调用URL]/predict`
- **Method**: `POST`
- **Body** (JSON):
  ```json
  {
    "userId": "2",
    "movieId": "2959"
  }
  ```

您应该会收到类似以下的成功响应：

```json
{
    "predicted_rating": 4.4,
    "movie_title": "Fight Club (1999)"
}
```

**恭喜！您已成功部署并测试了整个推荐系统。**

## 5. 项目文件结构

```
.aws_movie_recommender/
├── build_and_push.sh      # 用于构建和推送Docker镜像到ECR的自动化脚本
├── Dockerfile               # 定义了用于训练和服务的Docker容器环境
├── README.md                # 本文档
└── src/
    ├── lambda_function.py   # Lambda函数的代码，用于处理API请求和调用SageMaker
    ├── nginx.conf           # Nginx服务器的配置文件，在容器内使用
    ├── predictor.py         # Flask应用的封装，定义了API路由（/ping 和 /invocations）
    ├── serve                # SageMaker用于启动服务环境的可执行脚本
    ├── train                # SageMaker用于执行模型训练的可执行脚本
    └── wsgi.py              # WSGI入口文件，用于gunicorn启动Flask应用
```