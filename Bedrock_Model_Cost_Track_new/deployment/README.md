# 部署目录

## 目录结构

- `scripts/` - 部署和管理脚本
- `packages/` - Lambda部署包和其他二进制文件

## 部署脚本

### 主要脚本
- `deploy_all.sh` - 一键部署所有资源
- `create_api_gateway.sh` - 创建API Gateway
- `create_lambda_quick.sh` - 快速创建Lambda函数
- `verify_deployment.sh` - 验证部署状态

### 测试脚本
- `test_api_calls.sh` - API调用测试
- `test_concurrent_calls.sh` - 并发测试
- `test_cache_functionality.sh` - 缓存功能测试

## 部署包

### Lambda包
- `main-lambda*.zip` - 主Lambda函数包
- `cost-lambda*.zip` - 成本管理Lambda包

### 使用方法

1. **完整部署**:
   ```bash
   cd deployment/scripts
   ./deploy_all.sh
   ```

2. **验证部署**:
   ```bash
   ./verify_deployment.sh
   ```

3. **测试API**:
   ```bash
   ./test_api_calls.sh
   ```
