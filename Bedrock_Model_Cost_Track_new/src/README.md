# 源代码目录

## 目录结构

- `lambda/` - AWS Lambda函数代码
- `api/` - API相关代码和接口定义
- `utils/` - 通用工具函数和辅助代码

## Lambda函数

### 主要函数
- `lambda_function_resource_groups.py` - 主业务Lambda函数
- `lambda_function_cost_management.py` - 成本管理Lambda函数
- `session_tracking_enhancement.py` - 会话跟踪增强功能

### 功能说明
- 多租户请求处理
- Bedrock模型调用
- 成本计算和追踪
- EventBridge事件发布
- EMF指标生成
