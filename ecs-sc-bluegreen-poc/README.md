# ECS Service Connect 蓝绿部署 PoC

本项目包含了在 Amazon ECS 上使用 ECS Service Connect 实现蓝绿部署的示例代码和基础设施定义，详情请参考相关技术指南。

---

## 部署指南

本指南将引导您使用 AWS Cloud Development Kit (CDK) 完成项目的部署流程。

### 1. 先决条件

在开始部署之前，请确保您已安装并配置好以下工具：

*   **AWS CLI**: 用于与 AWS 服务进行交互。请确保已正确配置您的 AWS 凭证。
*   **Python 3.x**: 运行 CDK 应用程序的运行时环境。
*   **pip**: Python 包管理器，用于安装依赖。
*   **AWS CDK CLI**: 用于部署和管理 CDK 应用程序。可以通过 `npm install -g aws-cdk` 安装。
*   **Docker**: 用于构建和推送容器镜像。
*   **Git**: 用于代码版本控制。

### 2. 部署步骤

#### 2.1. 克隆代码库

```bash
git clone <your-repository-url>
cd ecs-sc-bluegreen-poc
```

#### 2.2. 构建并推送 Docker 镜像

在部署之前，您需要为蓝绿部署的两个版本（v1 和 v2）构建 Docker 镜像，并将其推送到 Amazon ECR (Elastic Container Registry)。

首先，登录到您的 ECR：

```bash
aws ecr get-login-password --region <your-aws-region> | docker login --username AWS --password-stdin <your-aws-account-id>.dkr.ecr.<your-aws-region>.amazonaws.com
```

然后，为 `blue` (v1) 版本构建并推送镜像：

```bash
docker build -t <your-ecr-repo-uri>:blue ./app/v1
docker push <your-ecr-repo-uri>:blue
```

接着，为 `green` (v2) 版本构建并推送镜像：

```bash
docker build -t <your-ecr-repo-uri>:green ./app/v2
docker push <your-ecr-repo-uri>:green
```

**注意**: 请将 `<your-aws-region>`, `<your-aws-account-id>`, 和 `<your-ecr-repo-uri>` 替换为您的实际信息。

#### 2.3. 安装 CDK 依赖

进入 `cdk` 目录并安装 Python 依赖：

```bash
cd cdk
pip install -r requirements.txt
```

#### 2.4. CDK 环境引导 (Bootstrap)

如果您的 AWS 账户和区域尚未进行 CDK 引导，您需要执行此步骤。这将创建必要的资源（如 S3 存储桶）来部署 CDK 应用程序。

```bash
cdk bootstrap aws://YOUR_ACCOUNT_ID/YOUR_REGION
```

**注意**: 请将 `YOUR_ACCOUNT_ID` 和 `YOUR_REGION` 替换为您的实际 AWS 账户 ID 和区域。

#### 2.5. 部署 CDK 栈

返回项目根目录，然后部署 CDK 栈：

```bash
cd .. # 返回到 ecs-sc-bluegreen-poc 根目录
cdk deploy
```

在提示时，输入 `y` 确认部署。

### 3. 验证部署

部署完成后，您可以通过以下方式进行验证：

1.  **获取 ALB URL**: 在 CDK 部署完成后，控制台会输出 Load Balancer 的 DNS 名称。您也可以通过 AWS 管理控制台的 EC2 -> Load Balancers 找到它。
2.  **访问应用**: 通过获取到的 ALB URL 访问您的应用程序。初始版本应为 "v1 (blue)"。
3.  **切换流量**: 要切换到 `green` 版本，您可能需要修改 CDK 栈中的相关配置（例如，在 `cdk/stack.py` 中修改服务配置），然后再次运行 `cdk deploy`。
4.  **验证更新**: 再次访问应用程序 URL，您应该能看到 "v2 (green)" 版本的内容。

### 4. 资源清理

如果您想删除本项目创建的所有资源，以避免产生额外费用，请运行以下命令：

```bash
cdk destroy
```

在提示时，输入 `y` 确认删除。