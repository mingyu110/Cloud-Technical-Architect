# 云计算与AI结合的技术架构 - 项目与实践

---

## 1. 仓库概述

本仓库 (`mingyu110/Cloud-Technical-Architect`) 是一个关于云计算和AI架构领域的项目、设计模式与最佳实践的综合代码库。每个子目录都代表一个独立的项目，旨在展示针对真实世界技术挑战的解决方案。

---

## 2. 项目列表

| 项目 (目录) | 核心功能与说明 | 主要技术栈 |
| :--- | :--- | :--- |
| [`AI_MCP/`](./AI_MCP/) | 基于MCP协议和AWS BedRock、AWS Lambda等在AWS云科技上构建的智能客服助手。 | `Python`, `AWS`, `Terraform`, `AI` |
| [`GitHubActions_AWS_Lambda/`](./GitHubActions_AWS_Lambda/) | 一套完整的CI/CD流水线，用于通过GitHub Actions在AWS Lambda上部署无服务器应用。 | `Node.js`, `AWS Lambda`, `GitHub Actions`, `CI/CD` |
| [`MLOps_CICD/`](./MLOps_CICD/) | 一个MLOps项目，演示了如何使用Terraform构建和管理从训练到部署的完整机器学习生命周期。 | `Python`, `Terraform`, `MLOps`, `AWS` |
| [`vehicle-monitoring/`](./vehicle-monitoring/) | 一个基于流式架构的实时车辆监控系统，通过AWS Kinesis和Lambda进行数据采集与处理。 | `Python`, `AWS Kinesis`, `AWS Lambda`, `Serverless` |
| [`Dev_MLOps/`](./Dev_MLOps/) | 基于Terraform、AWS EKS、Kubeflow和MLflow的端到端MLOps项目。 | `Python`, `Terraform`, `AWS EKS`, `MLOps` |
| [`Serverless_MCP_on_AWS/`](./Serverless_MCP_on_AWS_技术文档.md) | 在AWS上构建无服务器的MCP Server的技术方案选型分析。 | `AWS`, `Serverless`, `MCP` |
| [`bedrock_agent_deployment_project/`](./bedrock_agent_deployment_project/) | 一个完整的、可直接部署的示例，旨在演示如何将一个基于 Python 和 LangGraph 的 AI 代理，通过容器化技术部署到 **AWS Bedrock AgentCore**。 | `Python`, `AWS Bedrock`, `Docker`, `LangGraph` |
| [`aws-terraform-hybrid-dns/`](./aws-terraform-hybrid-dns/) | 一个通过Terraform实现的AWS混合云DNS解决方案，用于模拟本地数据中心与AWS之间的私有DNS解析。 | `Terraform`, `AWS`, `Route53`, `VPC Peering`, `DNS` |
| [`statefulset-pvc-resize-zero-downtime/`](./statefulset-pvc-resize-zero-downtime/) | 演示了如何在零停机的情况下，安全、平滑地对 Kubernetes StatefulSet 的持久化存储卷（PVC）进行扩容。 | `Kubernetes`, `StatefulSet`, `PVC`, `Zero-Downtime` |
| [`mlflow-sagemaker-model-build/`](./mlflow-sagemaker-model-build/) | 一个完整的、生产级的MLOps解决方案，演示了如何利用AWS SageMaker Pipelines和MLflow，构建一个自动化、可复现的模型构建与训练CI/CD管道。 | `Python`, `AWS SageMaker`, `MLflow`, `CI/CD`, `MLOps` |
| [`kubernetes/alibaba-cloud/`](./kubernetes/alibaba-cloud/aliyun-ack-advanced-network-security-practice.md) | 阿里云 ACK 中基于 Terway CNI 和 Karpenter 的高级网络安全实践 | `Kubernetes`, `阿里云 ACK`, `Terway CNI`, `Karpenter`, `网络安全`, `弹性伸缩` |
| [`异构云环境中间件选型与治理规范.md`](./异构云环境中间件选型与治理规范.md) | 在复杂的异构云（例如，AWS、阿里云、私有云）背景下，如何系统性地进行中间件的选型、部署、治理和优化的方法论和实践指南。 | `Middleware`, `Hybrid Cloud`, `Governance`, `Architecture` |

---

## 3. 贡献指南

欢迎任何形式的贡献，无论是添加新的项目、改进现有代码，还是修复文档中的错误。请遵循以下准则：

1.  **Fork & Clone**: 首先，Fork本仓库，然后将你的Fork克隆到本地。
2.  **创建分支**: 为你的修改创建一个新的特性分支 (`git checkout -b feature/YourFeatureName`)。
3.  **提交更改**: 进行修改，并创建清晰、有意义的提交信息。
4.  **发起Pull Request**: 将你的分支推送到GitHub，并向本仓库的`main`分支发起一个Pull Request。

请确保你的代码遵循仓库中已有的风格，并为任何新项目或重要功能添加清晰的`README.md`文件。