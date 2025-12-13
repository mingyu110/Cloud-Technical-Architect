# 基础设施代码

## 目录结构

- `cloudformation/` - AWS CloudFormation模板
- `terraform/` - Terraform配置文件

## CloudFormation模板

### 核心模板
- `01-dynamodb-tables.yaml` - DynamoDB表定义
- `02-iam-roles.yaml` - IAM角色和策略
- `03-lambda-function.yaml` - Lambda函数配置
- `04-monitoring.yaml` - CloudWatch监控配置
- `05-api-gateway.yaml` - API Gateway配置
- `06-sessions-table.yaml` - 会话表配置

### 部署顺序
1. DynamoDB表
2. IAM角色
3. Lambda函数
4. 监控配置
5. API Gateway
6. 会话表

## 资源依赖

```
DynamoDB ← Lambda ← API Gateway
    ↓
CloudWatch ← EventBridge ← SNS
```
