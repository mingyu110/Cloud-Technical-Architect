# 端到端 DevOps/MLOps 平台

### 1. 本仓库包含一个**完全自动化的 MLOps 平台**，使用以下技术：

- **基础设施即代码**（Terraform），使用AWS云服务作为基础设施
- **Kubernetes** 用于容器编排
- **KServe** 用于可扩展的模型服务
- **MLflow** 用于实验跟踪
- **XGBoost** 用于时间序列预测
- **Prometheus + Grafana** 用于监控
-  **CI/CD** 使用 GitHub Actions
- 模块化的 **Dockerized 微服务**
- 模块化的 **数据流水线**（数据摄取、训练、部署）

### 2. 详细介绍

可以参考本项目<u>/docs</u>目录下的[MLflow 和 KServe 在 Kubernetes 上的全流程 MLOps 部署（基于 Terraform 和 AWS EKS）](./docs/MLflow 和 KServe 在 Kubernetes 上的全流程 MLOps 部署（基于 Terraform 和 AWS EKS）)
