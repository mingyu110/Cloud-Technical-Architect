# E2E Dashboard告警测试

## 概述

这个目录包含Amazon Bedrock成本追踪系统的端到端Dashboard告警测试。

## 文件说明

- `single_test_with_dashboard.py` - 主要测试脚本，包含完整的Dashboard显示和告警触发
- `test_config.py` - 测试配置文件
- `run_dashboard_test.sh` - 快速运行脚本
- `README.md` - 本文档

## 快速开始

### 运行测试

```bash
# 方法1: 使用运行脚本
./run_dashboard_test.sh

# 方法2: 直接运行Python脚本
python3 single_test_with_dashboard.py
```

## 测试功能

### ✅ 实时监控Dashboard
- 预算使用情况显示
- 成本追踪
- Token使用统计
- 调用次数统计

### ✅ 告警触发测试
- **成本告警**: 5分钟内成本超过$0.01
- **Token告警**: 5分钟内Token超过1000

### ✅ 多次调用策略
- 使用短prompt避免API Gateway超时
- 通过多次调用累积达到告警阈值
- 实时显示累计统计

## 测试流程

1. **显示测试前状态** - 当前预算和使用情况
2. **执行多次API调用** - 使用短prompt累积成本和Token
3. **实时监控** - 显示每次调用的结果和累计数据
4. **触发告警** - 达到阈值时停止并显示告警信息
5. **等待指标更新** - 30秒等待CloudWatch指标更新
6. **显示测试后状态** - 对比测试前后的变化

## 告警配置

### Demo1 (demo1/websearch)
- 成本告警: $0.01 (5分钟)
- Token告警: 1000 tokens (5分钟)

### Demo2 (demo2/analytics)  
- 成本告警: $0.01 (5分钟)
- Token告警: 1000 tokens (5分钟)

## 预期结果

- ✅ 成功触发Token告警 (通常2-3次调用即可达到1000+ tokens)
- ✅ 实时Dashboard正常显示
- ✅ 告警邮件在2-3分钟内发送
- ✅ CloudWatch指标正常更新

## 故障排除

### API Gateway超时
- 已通过短prompt + 多次调用解决
- 单次调用控制在29秒内

### 告警未触发
- 检查CloudWatch告警配置
- 确认SNS主题订阅
- 验证指标数据是否正常发布

### Dashboard显示异常
- 检查DynamoDB表权限
- 验证CloudWatch指标权限
- 确认Redis连接状态

## 技术细节

- **架构**: Lambda (VPC) + Redis + DynamoDB + EventBridge + CloudWatch
- **响应时间**: 2-4秒 (热启动)
- **冷启动**: 10-15秒 (VPC ENI创建)
- **缓存**: Redis已启用，提供<1ms缓存访问

## 联系方式

- 邮箱: jackljx@amazon.com
- 告警通知: jackljx@amazon.com
