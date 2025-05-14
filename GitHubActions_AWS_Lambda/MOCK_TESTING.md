# Lambda 部署流水线 Mock 测试指南

本文档提供了如何使用 mock 测试工作流来验证 Lambda 部署流水线功能的说明。

## 测试环境

我们创建了以下文件来支持 mock 测试：

1. `.github/workflows/lambda-deploy-mock.yml` - 模拟部署工作流
2. `index.js` - 示例 Lambda 函数
3. `test/index.test.js` - Lambda 函数单元测试
4. `package.json` - 项目依赖配置

## 测试方法

### 1. 本地单元测试

在部署前，您可以在本地运行单元测试来验证 Lambda 函数的功能：

```bash
# 安装依赖
npm install

# 运行测试
npm test
```

### 2. 模拟工作流测试

GitHub Actions 模拟工作流允许您测试完整的部署流程，而无需实际部署到 AWS：

1. 在 GitHub 仓库页面，导航到 "Actions" 选项卡
2. 从左侧工作流列表中选择 "Mock AWS Lambda Deployment Test"
3. 点击 "Run workflow" 按钮
4. 选择要测试的场景：
   - `success` - 模拟成功的部署流程
   - `function_not_exist` - 模拟创建新函数的场景
   - `security_scan_fail` - 模拟安全扫描失败的场景
   - `deployment_fail` - 模拟部署失败的场景
5. 点击 "Run workflow" 开始测试

### 3. 查看测试结果

工作流完成后：

1. 点击测试运行记录
2. 查看各个作业的输出日志
3. 下载 "lambda-pipeline-test-report" 工件以获取详细的测试报告

## 测试场景说明

### 成功场景 (success)

模拟完整的部署流程，所有步骤都成功执行：
- 安全扫描通过
- 部署审批通过
- 函数更新成功
- 通知发送成功

### 函数不存在场景 (function_not_exist)

模拟首次部署场景，Lambda 函数尚未创建：
- 安全扫描通过
- 部署审批通过
- 检测到函数不存在，创建新函数
- 通知发送成功

### 安全扫描失败场景 (security_scan_fail)

模拟安全问题导致部署被阻止：
- 安全扫描失败（发现潜在安全漏洞）
- 部署流程中断，不执行后续步骤

### 部署失败场景 (deployment_fail)

模拟部署过程中出现错误：
- 安全扫描通过
- 部署审批通过
- 函数更新失败
- 通知发送包含失败信息

## 与实际部署流水线的对应关系

| Mock 工作流步骤 | 实际部署流水线步骤 | 测试内容 |
|----------------|-------------------|---------|
| Mock Security Scanning | Security Scanning | 代码安全分析、依赖项漏洞检查、密钥扫描 |
| Mock Deployment Approval | Deployment Approval | 部署审批流程 |
| Mock Lambda Deployment | Deploy Lambda Function | 函数创建/更新、配置验证、版本发布 |
| Mock Deployment Notification | Deployment Notification | 部署结果通知 |

## 注意事项

1. 此 mock 测试不会实际连接到 AWS 或部署任何资源
2. 模拟工作流主要用于验证流程逻辑和步骤顺序
3. 对于实际 AWS 集成测试，请使用专门的测试账户和环境
4. 在实际部署前，确保已正确配置 GitHub Secrets 和 AWS 权限 