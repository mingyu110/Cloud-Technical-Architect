#!/usr/bin/env python3
"""
增强日志工具 - 可轻松集成到现有测试脚本
"""
import time
from datetime import datetime
from typing import Dict, Any

try:
    from rich.console import Console
    RICH_AVAILABLE = True
except ImportError:
    RICH_AVAILABLE = False


class TestLogger:
    """测试日志记录器"""
    
    def __init__(self, enable_rich: bool = True):
        self.enable_rich = enable_rich and RICH_AVAILABLE
        if self.enable_rich:
            self.console = Console()
    
    def _get_timestamp(self) -> str:
        """获取时间戳"""
        return datetime.now().strftime("%H:%M:%S.%f")[:-3]
    
    def _print(self, message: str, style: str = None):
        """打印消息"""
        timestamp = self._get_timestamp()
        if self.enable_rich and style:
            self.console.print(f"[dim]{timestamp}[/dim] {message}", style=style)
        else:
            print(f"{timestamp} {message}")
    
    def info(self, message: str, emoji: str = "ℹ️"):
        """信息日志"""
        self._print(f"{emoji} {message}")
    
    def success(self, message: str):
        """成功日志"""
        self._print(f"✅ {message}", "green")
    
    def warning(self, message: str):
        """警告日志"""
        self._print(f"⚠️ {message}", "yellow")
    
    def error(self, message: str):
        """错误日志"""
        self._print(f"❌ {message}", "red")
    
    def api_call_start(self, call_num: int, prompt: str, tenant_id: str, app_id: str):
        """API调用开始"""
        short_prompt = prompt[:30] + "..." if len(prompt) > 30 else prompt
        self.info(f"调用 #{call_num}: '{short_prompt}' | 租户: {tenant_id} | 应用: {app_id}", "📞")
    
    def api_call_success(self, latency: float, cost: float, input_tokens: int, output_tokens: int):
        """API调用成功"""
        total_tokens = input_tokens + output_tokens
        self.success(f"响应成功 | 延迟: {latency:.2f}s | 成本: ${cost:.6f} | Token: {total_tokens} (输入:{input_tokens}, 输出:{output_tokens})")
    
    def api_call_failed(self, status_code: int, latency: float, error_msg: str = ""):
        """API调用失败"""
        msg = f"响应失败 | 状态码: {status_code} | 延迟: {latency:.2f}s"
        if error_msg:
            msg += f" | 错误: {error_msg}"
        self.error(msg)
    
    def cumulative_stats(self, call_count: int, total_cost: float, total_tokens: int):
        """累计统计"""
        self.info(f"累计统计 | 调用: {call_count} | 成本: ${total_cost:.6f} | Token: {total_tokens}", "📊")
    
    def threshold_check(self, cost_threshold: float, token_threshold: int, current_cost: float, current_tokens: int):
        """阈值检查"""
        cost_pct = (current_cost / cost_threshold) * 100 if cost_threshold > 0 else 0
        token_pct = (current_tokens / token_threshold) * 100 if token_threshold > 0 else 0
        
        cost_bar = self._create_progress_bar(cost_pct)
        token_bar = self._create_progress_bar(token_pct)
        
        self.info(f"阈值进度 | 成本: {cost_pct:.1f}% {cost_bar} | Token: {token_pct:.1f}% {token_bar}", "🎯")
    
    def _create_progress_bar(self, percentage: float, width: int = 10) -> str:
        """创建进度条"""
        filled = int(percentage / 10)  # 每10%一个方块
        filled = min(filled, width)
        bar = "█" * filled + "░" * (width - filled)
        return f"[{bar}]"
    
    def threshold_reached(self, threshold_type: str, current_value: float, threshold_value: float):
        """阈值达到"""
        self.warning(f"🚨 {threshold_type}告警阈值已达到! {current_value} >= {threshold_value}")
    
    def budget_info(self, budget_data: Dict[str, Any]):
        """预算信息"""
        if budget_data:
            total = budget_data.get('totalBudget', 0)
            balance = budget_data.get('balance', 0)
            used = total - balance
            usage_pct = (used / total * 100) if total > 0 else 0
            invocations = budget_data.get('invocations', 0)
            
            self.info(f"预算状态 | 总预算: ${total:.2f} | 已用: ${used:.4f} ({usage_pct:.1f}%) | 余额: ${balance:.4f} | 调用: {invocations}", "💰")
        else:
            self.warning("未找到预算信息")
    
    def metrics_info(self, metrics_data: Dict[str, Any]):
        """指标信息"""
        cost = metrics_data.get('cost_5min', 0)
        input_tokens = metrics_data.get('input_tokens_5min', 0)
        output_tokens = metrics_data.get('output_tokens_5min', 0)
        total_tokens = input_tokens + output_tokens
        
        if cost > 0 or total_tokens > 0:
            self.info(f"5分钟指标 | 成本: ${cost:.6f} | Token: {total_tokens} (输入:{input_tokens}, 输出:{output_tokens})", "📈")
        else:
            self.info("5分钟指标 | 暂无数据", "📈")
    
    def section_header(self, title: str):
        """章节标题"""
        if self.enable_rich:
            self.console.rule(f"[bold blue]{title}")
        else:
            print(f"\n{'='*50}")
            print(f"  {title}")
            print(f"{'='*50}")
    
    def test_summary(self, successful_calls: int, failed_calls: int, total_cost: float, total_tokens: int):
        """测试总结"""
        self.section_header("📋 测试总结")
        self.success(f"成功调用: {successful_calls}")
        if failed_calls > 0:
            self.error(f"失败调用: {failed_calls}")
        self.info(f"总成本: ${total_cost:.6f}", "💰")
        self.info(f"总Token: {total_tokens}", "🔢")
        
        if successful_calls > 0:
            avg_cost = total_cost / successful_calls
            avg_tokens = total_tokens / successful_calls
            self.info(f"平均成本: ${avg_cost:.6f}/调用", "📊")
            self.info(f"平均Token: {avg_tokens:.0f}/调用", "📊")


# 使用示例函数
def enhance_existing_test():
    """演示如何在现有测试中使用增强日志"""
    logger = TestLogger()
    
    # 在现有测试代码中添加这些日志调用：
    
    # 1. 测试开始
    logger.section_header("🚀 开始测试")
    
    # 2. API调用前
    logger.api_call_start(1, "什么是云计算？", "demo1", "test-app")
    
    # 3. API调用成功后
    logger.api_call_success(1.23, 0.001234, 15, 45)
    
    # 4. 累计统计
    logger.cumulative_stats(1, 0.001234, 60)
    
    # 5. 阈值检查
    logger.threshold_check(0.01, 1000, 0.001234, 60)
    
    # 6. 预算信息
    logger.budget_info({
        'totalBudget': 10.0,
        'balance': 6.1,
        'invocations': 890
    })
    
    # 7. 测试总结
    logger.test_summary(8, 2, 0.008765, 480)


if __name__ == "__main__":
    enhance_existing_test()
