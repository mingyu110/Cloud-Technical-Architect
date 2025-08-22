# AWS Landing Zone 方案落地实践指南

## 摘要

AWS Landing Zone 是一个基于安全和合规最佳实践的、架构良好、可扩展的多账户AWS环境。本文档旨在为企业提供一套完整的AWS Landing Zone落地实践指南，内容涵盖从初期构建选项的比较，到关键决策的考量因素，再到自动化合规体系的建立，最后落脚于具体的构建建议，以帮助组织高效、安全地开启云上之旅。

---

## 1. 构建选项 (Build Options)

企业在启动Landing Zone项目时，面临三种主要构建路径。每种路径对应不同的技术能力要求、定制化程度和管理开销。

### 1.1. AWS Control Tower (托管服务)

AWS Control Tower是AWS官方推出的托管服务，旨在通过自动化方式快速建立一个符合最佳实践的Landing Zone。它集成了AWS Organizations, IAM Identity Center, AWS Config等核心服务。

- **适用场景**: 适合AWS新用户、中小型组织或任何需要快速、标准化部署且不希望投入过多资源进行底层维护的团队。
- **核心优势**:
    - **快速部署**: 仅需数小时即可建立一个基础环境。
    - **自动化治理**: 内置“守栏 (Guardrails)”（基于服务控制策略SCPs和AWS Config规则），提供预防性和检测性控制。
    - **简化账户管理**: 通过账户工厂 (Account Factory) 自动化创建和配置新账户。
- **架构图**:
    <img src="https://docs.aws.amazon.com/images/prescriptive-guidance/latest/migration-aws-environment/images/aws-control-tower.png" alt="AWS services included in AWS Control Tower setup." style="zoom:80%;" />

​       <img src="https://miro.medium.com/v2/resize:fit:1120/1*llH_zSKFNDI4wz4lh08CwQ.png" alt="img" style="zoom:80%;" />

### 1.2. Landing Zone Accelerator (LZA)

LZA是一个开源的、基于AWS CDK（云开发工具包）的解决方案，它提供了比Control Tower更强大的定制能力和更广泛的服务集成。

- **适用场景**: 适合有高度监管要求（如金融、医疗行业）或复杂合规需求的组织。
- **核心优势**:
    - **高度可定制**: 通过YAML配置文件进行管理，支持超过35种AWS服务的深度配置。
    - **GitOps工作流**: 采用IaC（基础设施即代码）和GitOps模式，所有变更通过代码提交和CI/CD管道执行，便于审计和版本控制。
    - **合规框架支持**: 内置针对多种全球及行业合规框架（如FedRAMP, CMMC, PCI-DSS）的模板。
- **架构图**:
    ![LZA Architecture](https://cdn.prod.website-files.com/6527fe8ad7301efb15574cc7/66b5d5f8be9615547478208d_AD_4nXe5I6Z6zvOqedjI85kn7iQRjqKwwKiGS4lqOtOwt-_jhUHLOTjm8rFLwp4VpuwoJOf0HNDRmA3k3FU3k2uGcnXRho0hZMBVGRiGZSVDmFDyVkt1SgXKO95DUf5pYoPsHxP6lU1UyI4sASovA0b8kZmODUMf.png)

### 1.3. 自定义构建 (Custom Build)

对于拥有资深AWS专家团队和独特业务需求的组织，可以选择从零开始，完全自定义构建Landing Zone。

- **适用场景**: 需要对环境有完全控制权，且现有方案无法满足其特定网络、安全或运营模式的大型企业。
- **核心挑战**:
    - **高技术门槛**: 要求团队对AWS Organizations, IAM, CloudFormation, SCPs等服务有深入理解。
    - **高昂的维护成本**: 组织需自行负责整个平台的开发、维护和迭代。

---

## 2. 选择考虑 (Selection Considerations)

选择最合适的Landing Zone方案需要综合评估以下几个关键维度：

- **组织规模与复杂性**: 
  - **小型团队/新用户**: 推荐从AWS Control Tower入手，其低复杂度和高自动化能快速带来价值。
  - **大型企业/多团队**: LZA或自定义构建能更好地满足多业务单元、复杂审批流和账单分离的需求。

- **安全与合规要求**:
  - **通用最佳实践**: Control Tower提供的基础守栏已能满足大部分安全需求。
  - **严格监管行业**: LZA对特定合规框架（如HIPAA, GDPR, PCI-DSS）的内置支持是巨大优势。自定义构建则能实现最精细化的合规控制。

- **网络架构**:
  - **简单网络**: Control Tower可以配置基础的VPC。
  - **复杂/混合云网络**: 若需要复杂的VPC对等连接、与本地数据中心的专线(Direct Connect)或中转网关(Transit Gateway)，LZA和自定义构建提供了必要的灵活性。

- **运营效率与成本**:
  - **自动化程度**: Control Tower和LZA都提供了高度的自动化，减少了手动操作。但LZA的部署和变更流程（基于CloudFormation）可能比Terraform等工具慢，需要考虑团队的接受度。
  - **成本考量**: Landing Zone本身会产生费用（如AWS Config规则、GuardDuty、CloudTrail等），需预估每月的基础成本，并建立成本监控和优化机制。

- **技术栈与团队技能**:
  - **IaC工具偏好**: LZA基于AWS CDK和CloudFormation。如果团队更熟悉Terraform或Pulumi，可能会倾向于自定义构建或寻找基于这些工具的第三方解决方案。

---

## 3. 自动化合规 (Automated Compliance)

自动化是Landing Zone实现持续合规的核心。其体系主要由预防性控制和检测性控制构成。

### 3.1. 预防性守栏 (Preventive Guardrails)

通过在源头限制不合规的操作，从根本上杜绝安全风险。

- **服务控制策略 (SCPs)**: 这是最强大的预防性工具。通过AWS Organizations，可以定义SCPs来限制特定AWS账户或组织单元（OU）内的IAM用户和角色可以执行的操作。例如，可以创建一条SCP来禁止任何账户（除特定授权外）删除CloudTrail日志或修改安全配置。

### 3.2. 检测性守栏 (Detective Guardrails)

持续监控资源配置和活动，发现并告警不合规的状态。

- **AWS Config**: 自动记录所有AWS资源的配置变更，并基于预设规则（如“所有S3存储桶必须加密”）评估合规性。这是实现持续监控和审计的基础。
- **AWS Security Hub**: 聚合来自AWS Config, GuardDuty, IAM Access Analyzer等多个安全服务的发现，并根据CIS、AWS基础安全最佳实践等标准进行检查，提供一个统一的安全态势视图。
- **Amazon GuardDuty**: 智能威胁检测服务，通过分析VPC流日志、CloudTrail事件日志和DNS日志来识别恶意活动和未授权行为。
- **IAM Access Analyzer**: 分析资源策略，识别哪些资源（如S3存储桶、IAM角色）被授予了外部访问权限，防止权限配置不当。

### 3.3. 自动化部署与修复

- **基础设施即代码 (IaC)**: 使用AWS CloudFormation、CDK或Terraform来定义和部署所有Landing Zone的基础设施。这确保了环境的一致性、可重复性和版本可控性。
- **CI/CD 流水线**: 结合GitOps工作流，所有对Landing Zone配置的变更都通过代码审查和自动化管道（如AWS CodePipeline）进行部署，确保变更的安全和可追溯。

---

## 4. 构建建议 (Build Recommendations)

基于实践经验，以下是落地Landing Zone时的具体构建建议。

### 4.1. 账户结构设计

采用模块化的多账户策略是最佳实践。一个典型的结构应至少包含以下几类账户：

- **管理账户 (Management Account)**: 权限最高，仅用于管理AWS Organizations、账单和创建其他核心账户，应尽可能少地使用。
- **核心账户 (Core Accounts)**: 由云平台团队管理，职责分离。
  - **安全账户 (Security)**: 用于部署和管理安全服务（如GuardDuty, Security Hub），并作为安全运维的统一入口。
  - **日志归档账户 (Logs & Keys)**: 集中存储所有账户的CloudTrail、Config等关键审计日志，并统一管理KMS密钥。
  - **网络账户 (Infra)**: 统一管理网络资源，如Transit Gateway、集中的网络出口VPC、与本地的VPN/Direct Connect连接等。
- **应用账户 (Application Accounts)**: 根据业务线和环境（生产/非生产）进行隔离，以实现最小爆炸半径、清晰的成本归属和简化的权限管理。
- **沙箱账户 (Sandbox)**: 用于测试新的IaC模板、SCPs或服务，确保变更不会影响生产环境。

**建议的账户架构图**:
![Account Structure](https://miro.medium.com/v2/resize:fit:1120/1*umPvCDChZF6RWDMJc7_kaQ.png)

### 4.2. 身份与访问管理

- **统一身份源**: 使用 **AWS IAM Identity Center (原AWS SSO)** 作为所有人工访问的唯一入口。它能与企业现有身份提供商（IdP）集成，并为用户提供基于临时凭证的CLI/API访问，杜绝长期Access Key的使用。

- **权限策略**: 遵循最小权限原则。为不同职责（如应用开发者、数据库管理员、网络工程师）创建标准化的权限集 (Permission Sets)，并按需分配给不同账户中的用户组。

- **角色优于用户**: 严格限制在成员账户中创建IAM用户。所有跨账户访问和应用对AWS服务的访问都应通过IAM角色实现。

  <img src="https://miro.medium.com/v2/resize:fit:1120/1*rqvX-o2xUyNksu9Mn3FUFw.png" alt="img" style="zoom:80%;" />

### 4.3. 网络设计

- **中心辐射模型 (Hub-and-Spoke)**: 使用 **AWS Transit Gateway** 作为网络中心（Hub），连接所有VPC（Spokes）。这种架构简化了VPC间的路由，并易于扩展。

- **集中式网络出口**: 在网络账户中创建一个独立的Egress VPC，所有应用VPC通过Transit Gateway将出站流量路由到此VPC，再通过NAT网关和防火墙访问互联网。这便于统一监控和保护出站流量。

  <img src="https://miro.medium.com/v2/resize:fit:1120/1*z-OX8qQ2yYsiPcWLFAgzMQ.png" alt="img" style="zoom:80%;" />

### 4.4. 日志与监控

- **日志集中化**: 将所有账户的CloudTrail日志、Config快照、VPC流日志等统一发送到日志归档账户的S3存储桶中，并设置不可篡改的生命周期策略。

- **应用团队可访问性**: 虽然审计日志集中存储，但应在每个应用账户内为团队提供查询其自身日志的便捷方式（如通过CloudTrail Lake或CloudWatch Logs Insights），以支持日常调试和排错。

  <img src="https://miro.medium.com/v2/resize:fit:1120/1*AwXAmLarAdFxzSLpWvdKlQ.png" alt="img" style="zoom:80%;" />

---

## 5. 参考文档 (Reference Documents)

#### AWS Control Tower
- **[AWS Control Tower User Guide](https://docs.aws.amazon.com/controltower/latest/userguide/what-is-control-tower.html)**: AWS Control Tower 官方用户指南，提供全面的设置和管理说明。

#### Landing Zone Accelerator (LZA)
- **[Landing Zone Accelerator on AWS](https://aws.amazon.com/solutions/implementations/landing-zone-accelerator-on-aws/)**: LZA 官方解决方案页面，概述其特性和优势。
- **[LZA Implementation Guide](https://docs.aws.amazon.com/solutions/latest/landing-zone-accelerator-on-aws/implementation-guide.html)**: LZA 详细的官方实施指南。
- **[GitHub: Landing Zone Accelerator on AWS](https://github.com/awslabs/landing-zone-accelerator-on-aws)**: LZA 的开源代码库。

#### AWS 规范性指导 (Prescriptive Guidance)
- **[Building a landing zone](https://docs.aws.amazon.com/prescriptive-guidance/latest/migration-aws-environment/building-landing-zones.html)**: 来自AWS官方的、关于构建Landing Zone的规范性指导和最佳实践。

#### 核心框架与概念
- **[AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected)**: AWS官方的最佳实践框架，指导如何设计和运营可靠、安全、高效、经济和可持续的云中系统，是Landing Zone设计的理论基础。
