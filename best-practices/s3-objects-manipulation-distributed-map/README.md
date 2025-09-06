# AWS Step Functions 分布式 Map 实现大规模 S3 对象处理

本项目是一个基于 AWS CDK 的示例模板，旨在探索如何利用 AWS Step Functions 的分布式 Map（Distributed Map）功能，来满足大规模并行处理的需求。

该示例参考了 [AWS 官方文档](https://docs.aws.amazon.com/step-functions/latest/dg/use-dist-map-orchestrate-large-scale-parallel-workloads.html) 以及 [AWS 官方博客](https://aws.amazon.com/blogs/aws/step-functions-distributed-map-a-serverless-solution-for-large-scale-parallel-data-processing/) 中探讨的概念与实践。

**重要提示**: 此应用使用了多种 AWS 服务，在免费套餐额度用尽后，可能会产生相关费用。具体定价请参考 [AWS 定价页面](https://aws.amazon.com/pricing/)。您需要对由此产生的所有 AWS 费用负责。本示例不提供任何形式的保证。

---

## 环境要求

在开始部署前，请确保您已安装并配置好以下工具：

*   [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
*   [Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
*   [AWS CDK](https://docs.aws.amazon.com/cdk/v2/guide/getting_started.html#getting_started_install)

---

## 项目结构

本代码仓库包含以下几个核心目录：

*   `Common`: 存放所有工作流共享的通用资源，如 S3 存储桶和 SNS 主题。
*   `SimpleDistributedMaps`: 包含一个简单的分布式 Map 工作流示例。
*   `NestedDistributedMap`: 包含一个嵌套的、更复杂的分布式 Map 工作流示例。
*   `resources`: 存放项目所需的静态资源，如配置文件和架构图。

---

## 部署与测试指南

请遵循以下步骤完成项目的部署与测试。

### **第一步：部署通用资源 (Common)**

此步骤将创建被后续所有工作流使用的 S3 存储桶和 SNS 主题。

```bash
cd Common && npm install && npm run cdk:deploy
```

### **第二步：部署简单分布式 Map (SimpleDistributedMaps)**

此步骤将部署一个简单的工作流，演示分布式 Map 的基本用法。

```bash
cd SimpleDistributedMaps && npm install && npm run cdk:deploy
```

其架构如下图所示：

![简单工作流架构图](https://github.com/mingyu110/tech-blog-/blob/main/static/images/Simple%20Distributed%20Map%20Architecture.png)

### **第三步：部署嵌套分布式 Map (NestedDistributedMap)**

此步骤将部署一个更复杂的工作流，展示分布式 Map 的嵌套使用场景。

```bash
cd NestedDistributedMap && npm install && npm run cdk:deploy
```

其架构如下图所示：

![嵌套工作流架构图](https://github.com/mingyu110/tech-blog-/blob/main/static/images/Nested%20Distributed%20Map%20Architecture.png)

### **第四步：准备S3测试数据**

在部署完成后，运行以下命令来生成大量测试文件，并将其上传到 S3 存储桶，作为状态机工作流的输入数据源。

**注意**: 请将命令中的 `<S3-Bucket-Name>` 替换为 **第一步** 中创建的 S3 存储桶的名称。您可以在 AWS Parameter Store 中找到该名称。

```shell
cd resources && for j in {1..1000}; do mkdir assets && for i in {1..100}; do cp example1.json assets/"example$j-$i.json"; done; aws s3 sync assets s3://<S3-Bucket-Name>; rm -rf assets ; done;
```
这个脚本会循环1000次，每次迭代中复制100个 `example.json` 文件，然后将这些文件同步到您的 S3 存储桶中。

### **第五步：运行与测试**

您可以直接在 AWS Step Functions 控制台触发状态机执行，无需提供任何输入负载。

---

## 资源清理

如果您需要销毁在本项目中创建的所有资源，请在各个模块目录（`SimpleDistributedMaps`, `NestedDistributedMap`, `Common`）下执行以下命令：

```bash
npm run cdk:destroy
```

> **提示**: `Common` 模块的销毁脚本会尝试自动删除 S3 存储桶中的所有对象。但如果文件数量过多，此操作可能会失败。为了避免这种情况，建议您在执行销毁命令前，先在 AWS 管理控制台中手动清空 S3 存储桶，这样速度更快。
