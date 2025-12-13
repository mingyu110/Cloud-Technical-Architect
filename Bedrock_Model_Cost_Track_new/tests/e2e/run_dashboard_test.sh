#!/bin/bash

# Dashboard告警测试运行脚本
# 运行带dashboard的完整告警指标测试

echo "🎬 启动Dashboard告警测试"
echo "================================"
echo "📊 测试内容:"
echo "  - 实时成本监控"
echo "  - Token使用追踪"
echo "  - 告警阈值触发"
echo "  - Dashboard显示"
echo "================================"

python3 single_test_with_dashboard.py

echo ""
echo "📧 提示: 告警邮件将在2-3分钟内发送"
echo "🔍 可以检查CloudWatch告警状态确认触发"
