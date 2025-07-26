# MLflow 和 KServe 在 Kubernetes 上的全流程 MLOps 部署（基于 Terraform 和 AWS EKS）

## 1. 引言

本文档描述了如何使用 Terraform 在 AWS 上创建基础设施（包括 Amazon EKS 集群、VPC、S3 和 ECR），结合 MLflow 和 KServe 构建一个可扩展的机器学习操作（MLOps）管道，实现从模型训练到生产环境部署的完整流程。本指南适用于希望在云环境中部署生产级 MLOps 管道的团队。云基础资源以AWS为例并使用 Terraform 自动化基础设施管理。

<img src="https://miro.medium.com/v2/resize:fit:1120/1*aJQrRR3h3CHBib_ijc7l1A.png" alt="img" style="zoom:67%;" />

---

## 2. 背景与目标

### 2.1 背景
机器学习模型从实验到生产部署面临诸多挑战，包括**模型管理、扩展性、可靠性和自动化**。本文档通过 AWS EKS 和 Terraform 提供高可用性、可扩展性和云服务集成。

### 2.2 目标
- 使用 Terraform 自动化创建 AWS 基础设施（EKS、VPC、S3、ECR）。
- 实现端到端的 MLOps 管道：模型训练、注册、部署和推理。
- 提供生产级功能，如自动扩展、负载均衡和监控。

---

## 3. 关键技术与原理

### 3.1 Terraform
- **定义**：Terraform 是一个基础设施即代码（IaC）工具，通过声明式配置文件（`.tf` 文件）定义和管理云资源。
- **工作原理**：
  - 使用提供者（如 `aws`）与云 API 交互，创建资源（如 EKS 集群、S3 存储桶）。
  - 维护状态文件（`terraform.tfstate`）跟踪资源状态，支持增量更新和销毁。
  - 支持模块化配置（如 `terraform-aws-modules/eks`）。
- **作用**：自动化创建 EKS 集群、VPC、IAM 角色、S3 存储桶和 ECR 仓库。

### 3.2 Amazon EKS
- **定义**：AWS 托管的 Kubernetes 服务，管理控制平面，用户管理数据平面（工作节点）。
- **核心组件**：
  - **控制平面**：托管 Kubernetes API 和 etcd，高可用性跨多可用区。
  - **节点组**：运行在 EC2 实例上的工作节点，托管 KServe 和 MLflow 的 Pod。
  - **IAM 集成**：通过 IRSA 为 Pod 分配权限。
- **优势**：高可用性、自动扩展、与 AWS 服务集成。

### 3.3 Amazon S3 和 ECR
- **S3**：对象存储服务，用于存储 MLflow 模型和工件。
- **ECR**：托管 Docker 镜像仓库，存储 MLflow 模型的推理镜像。

### 3.4 KServe
- **定义**：基于 Kubernetes 的模型服务框架，支持多框架推理。
- **功能**：自动扩展、金丝雀发布、REST/gRPC 协议支持。
- **工作原理**：通过 `InferenceService` CRD 部署模型，结合 Istio 和 Knative 实现流量管理和无服务器功能。

### 3.5 MLflow
- **定义**：管理机器学习生命周期的开源平台。
- **组件**：实验跟踪、模型注册、部署。
- **工作原理**：通过 API 记录实验数据，模型存储在 S3，推理通过 MLServer 实现。

---

## 4. 环境准备

### 4.1 依赖工具
- **Terraform**：https://www.terraform.io/downloads.html
- **AWS CLI**：配置 IAM 凭证（`aws configure`）。
- **kubectl**：与 EKS 交互。
- **AWS 账户**：具有创建 EKS、VPC、S3、ECR 权限。

### 4.2 Terraform 基础设施配置

#### 4.2.1 文件结构
```plaintext
mlops-infra/
├── main.tf              # 主配置文件
├── variables.tf         # 变量定义
├── outputs.tf           # 输出定义
├── provider.tf          # AWS 提供者配置
```

#### 4.2.2 provider.tf

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.5.0"
}

provider "aws" {
  region = var.aws_region
}
```

#### 4.2.3 variables.tf

```hcl
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "mlops-cluster"
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for MLflow models"
  type        = string
  default     = "mlops-models-bucket"
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository for MLflow models"
  type        = string
  default     = "wine-model"
}
```

#### 4.2.4 main.tf

```hcl
# VPC 模块
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# EKS 模块
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.24"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    default = {
      min_size     = 1
      max_size     = 3
      desired_size = 2
      instance_types = ["t3.medium"]
    }
  }

  tags = {
    Environment = "mlops"
  }
}

# S3 存储桶
resource "aws_s3_bucket" "mlflow_models" {
  bucket = var.s3_bucket_name
  tags = {
    Name = "MLflow Models"
  }
}

resource "aws_s3_bucket_ownership_controls" "mlflow_models" {
  bucket = aws_s3_bucket.mlflow_models.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "mlflow_models" {
  depends_on = [aws_s3_bucket_ownership_controls.mlflow_models]
  bucket = aws_s3_bucket.mlflow_models.id
  acl    = "private"
}

# ECR 仓库
resource "aws_ecr_repository" "wine_model" {
  name = var.ecr_repository_name
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}
```

#### 4.2.5 outputs.tf

```hcl
output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "s3_bucket_name" {
  description = "S3 bucket name for MLflow models"
  value       = aws_s3_bucket.mlflow_models.bucket
}

output "ecr_repository_uri" {
  description = "ECR repository URI for wine-model"
  value       = aws_ecr_repository.wine_model.repository_url
}
```

#### 4.2.6 执行 Terraform

1. 初始化：

   ```bash
   terraform init
   ```

2. 预览计划：

   ```bash
   terraform plan
   ```

3. 应用配置：

   ```bash
   terraform apply
   ```

4. 配置 kubectl：

   ```bash
   aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name}
   ```

------

### 5. 部署 MLflow 和 KServe5.1 安装 KServe 及其依赖

#### 5.1 安装 KServe 及其依赖

1. 安装 Istio：

   ```bash
   istio_version=1.17.2
   curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$istio_version sh -
   istio-$istio_version/bin/istioctl install --set profile=demo -y
   ```

2. 安装 Knative 和 Cert-manager：

   - 参考 KServe 官方 QuickStart（https://kserve.github.io/website/get_started/）。

3. 安装 KServe：

   ```bash
   kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.10.0/kserve.yaml
   kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.10.0/kserve-runtimes.yaml
   ```

#### 5.2 模型训练与注册

1. 配置 MLflow 存储后端：

   ```python
   import os
   os.environ["MLFLOW_S3_ENDPOINT_URL"] = "https://s3.amazonaws.com"
   os.environ["AWS_ACCESS_KEY_ID"] = "<your-access-key>"
   os.environ["AWS_SECRET_ACCESS_KEY"] = "<your-secret-key>"
   ```

2. 训练模型（葡萄酒质量预测）：

   ```python
   import mlflow
   import mlflow.sklearn
   from sklearn.ensemble import RandomForestRegressor
   from sklearn.datasets import load_wine
   
   mlflow.set_tracking_uri("http://<mlflow-server>")
   mlflow.set_experiment("wine-quality")
   
   wine = load_wine()
   X, y = wine.data, wine.target
   
   with mlflow.start_run():
       model = RandomForestRegressor()
       model.fit(X, y)
       mlflow.sklearn.log_model(model, "wine-model", registered_model_name="WineQualityModel")
   ```

3. 模型存储：模型上传至 S3（s3://mlops-models-bucket/wine-model）。

#### 5.3 构建和推送 Docker 镜像

1. 构建镜像：

   ```bash
   mlflow models build-docker -m "runs:/<run_id>/wine-model" -n wine-model:latest
   ```

2. 推送至 ECR：

   ```bash
   aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin <account-id>.dkr.ecr.${var.aws_region}.amazonaws.com
   docker tag wine-model:latest <account-id>.dkr.ecr.${var.aws_region}.amazonaws.com/wine-model:latest
   docker push <account-id>.dkr.ecr.${var.aws_region}.amazonaws.com/wine-model:latest
   ```

#### 5.4 配置 KServe InferenceService创建 wine-inference.yaml：

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: wine-model
  namespace: kserve-inference
spec:
  predictor:
    model:
      modelFormat:
        name: sklearn
      storageUri: "s3://mlops-models-bucket/wine-model"
      runtimeVersion: "2.12.0"
      protocolVersion: "v2"
```

或使用 ECR 镜像：

```yaml
spec:
  predictor:
    containers:
    - image: <account-id>.dkr.ecr.${var.aws_region}.amazonaws.com/wine-model:latest
      name: kserve-container
      args:
      - --model_name=wine-model
      - --protocol=v2
```

#### 5.5 部署和测试

1. 部署模型：

   ```bash
   kubectl apply -f wine-inference.yaml
   ```

2. 获取推理 URL：

   ```bash
   kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
   ```

3. 测试推理：

   ```bash
   curl -H "Content-Type: application/json" http://<alb-hostname>/v2/models/wine-model/infer \
   -d '{"inputs": [{"name": "input-0", "shape": [1, 13], "datatype": "FP32", "data": [7.4, 0.7, 0.0, 1.9, 0.076, 11.0, 34.0, 0.9978, 3.51, 0.56, 9.4, 5.0, 0.0]}]}'
   ```

------

### 6. 最佳实践与注意事项

1. IAM 权限：

   - 为 EKS 节点组和 KServe Pod 配置 IRSA，授予 S3 和 ECR 权限：

     ```hcl
     module "eks" {
       node_groups = {
         default = {
           iam_role_additional_policies = {
             s3 = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
             ecr = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
           }
         }
       }
     }
     ```

2. 安全性：

   - 使用 AWS Secrets Manager 存储 MLflow 凭证。
   - 配置 S3 加密和访问控制。

3. 监控：

   - 使用 Amazon CloudWatch 监控 EKS 和 KServe。
   - 集成 Prometheus 和 Grafana 监控推理性能。

4. 成本优化：

   - 配置 EKS 节点组自动扩展。
   - 使用 KServe 的零扩展降低空闲成本。

5. 清理资源：

   ```bash
   terraform destroy
   ```

------

### 7. 结论

通过 Terraform 在 AWS EKS 上部署 MLflow 和 KServe，实现自动部署和管理云基础设施资源。Terraform 自动化创建了 VPC、EKS 集群、S3 存储桶和 ECR 仓库，简化了基础设施管理。通过实现 MLOps 工作流，并并通过 AWS 的负载均衡和自动扩展提升了可靠性，适合生产环境部署。