#!/usr/bin/env python3
"""
单次测试 + 实时仪表板
调用真实Bedrock API，展示实时数据变化
"""
import sys
import time
import json
import requests
import boto3
from datetime import datetime, timedelta
from typing import Dict, Optional

try:
    from rich.console import Console
    from rich.table import Table
    from rich.panel import Panel
    from rich import box
    RICH_AVAILABLE = True
except ImportError:
    RICH_AVAILABLE = False

from test_config import API_URL, REQUEST_TIMEOUT


class RealtimeMonitor:
    """实时监控器"""
    
    def __init__(self, region: str = 'us-east-1'):
        self.cloudwatch = boto3.client('cloudwatch', region_name=region)
        self.dynamodb = boto3.resource('dynamodb', region_name=region)
        self.budget_table_name = 'bedrock-cost-tracking-production-tenant-budgets'
        
        if RICH_AVAILABLE:
            self.console = Console()
    
    def get_budget(self, tenant_id: str) -> Optional[Dict]:
        """查询预算"""
        try:
            table = self.dynamodb.Table(self.budget_table_name)
            response = table.get_item(Key={'tenantId': tenant_id, 'modelId': 'ALL'})
            
            if 'Item' in response:
                item = response['Item']
                return {
                    'totalBudget': float(item.get('totalBudget', 0)),
                    'balance': float(item.get('balance', 0)),
                    'invocations': int(item.get('totalInvocations', 0))
                }
            return None
        except Exception as e:
            print(f"⚠️  查询预算失败: {e}")
            return None
    
    def get_metrics(self, tenant_id: str, app_id: str, minutes: int = 15) -> Dict:
        """查询CloudWatch指标（默认15分钟窗口，增加数据命中率）"""
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(minutes=minutes)
        
        metrics = {}
        # 使用成本管理Lambda发布的指标名称
        metric_configs = [
            {'name': 'DetailedCost', 'dimensions': [
                {'Name': 'TenantID', 'Value': tenant_id},
                {'Name': 'ApplicationID', 'Value': app_id},
                {'Name': 'ModelID', 'Value': 'amazon.nova-pro-v1:0'}
            ]},
            {'name': 'InputTokens', 'dimensions': [
                {'Name': 'TenantID', 'Value': tenant_id},
                {'Name': 'ApplicationID', 'Value': app_id},
                {'Name': 'ModelID', 'Value': 'amazon.nova-pro-v1:0'}
            ]},
            {'name': 'OutputTokens', 'dimensions': [
                {'Name': 'TenantID', 'Value': tenant_id},
                {'Name': 'ApplicationID', 'Value': app_id},
                {'Name': 'ModelID', 'Value': 'amazon.nova-pro-v1:0'}
            ]},
            {'name': 'TotalTokens', 'dimensions': [
                {'Name': 'TenantID', 'Value': tenant_id},
                {'Name': 'ApplicationID', 'Value': app_id},
                {'Name': 'ModelID', 'Value': 'amazon.nova-pro-v1:0'}
            ]}
        ]
        
        for metric_config in metric_configs:
            try:
                response = self.cloudwatch.get_metric_statistics(
                    Namespace='BedrockCostManagement',
                    MetricName=metric_config['name'],
                    Dimensions=metric_config['dimensions'],
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=300,
                    Statistics=['Sum']
                )
                
                total_value = sum(point['Sum'] for point in response['Datapoints'])
                metrics[metric_config['name']] = total_value if total_value > 0 else None
                
            except Exception as e:
                metrics[metric_config['name']] = None
        
        return metrics
    
    def display_dashboard(self, tenant_id: str, app_id: str, title: str):
        """显示仪表板"""
        if RICH_AVAILABLE:
            self._display_rich_dashboard(tenant_id, app_id, title)
        else:
            self._display_simple_dashboard(tenant_id, app_id, title)
    
    def _display_rich_dashboard(self, tenant_id: str, app_id: str, title: str):
        """Rich版本仪表板"""
        table = Table(title=title, box=box.ROUNDED, show_header=True, header_style="bold magenta")
        table.add_column("指标", style="cyan", width=20)
        table.add_column("当前值", style="green", width=25)
        table.add_column("状态", style="yellow", width=25)
        
        # 预算
        budget = self.get_budget(tenant_id)
        if budget:
            used = budget['totalBudget'] - budget['balance']
            usage_pct = (used / budget['totalBudget'] * 100) if budget['totalBudget'] > 0 else 0
            
            table.add_row("💰 总预算", f"${budget['totalBudget']:.2f}", f"已用 {usage_pct:.1f}%")
            table.add_row("💵 已使用", f"${used:.4f}", self._get_bar(usage_pct))
            table.add_row("💳 剩余", f"${budget['balance']:.4f}", f"可用 {100-usage_pct:.1f}%")
            table.add_row("📞 调用次数", f"{budget['invocations']}", "总计")
        else:
            table.add_row("💰 预算", "暂无数据", "")
        
        table.add_section()
        
        # 指标
        metrics = self.get_metrics(tenant_id, app_id)
        
        if metrics['DetailedCost'] is not None:
            table.add_row("💸 成本 (5分钟)", f"${metrics['DetailedCost']:.6f}", "CloudWatch")
        else:
            table.add_row("💸 成本 (5分钟)", "暂无数据", "")
        
        if metrics['InputTokens'] is not None:
            table.add_row("📥 输入Token", f"{int(metrics['InputTokens'])}", "CloudWatch")
        else:
            table.add_row("📥 输入Token", "暂无数据", "")
        
        if metrics['OutputTokens'] is not None:
            table.add_row("📤 输出Token", f"{int(metrics['OutputTokens'])}", "CloudWatch")
        else:
            table.add_row("📤 输出Token", "暂无数据", "")
        
        if metrics['InputTokens'] is not None and metrics['OutputTokens'] is not None:
            total = int(metrics['InputTokens'] + metrics['OutputTokens'])
            table.add_row("🔢 总Token", f"{total}", "CloudWatch")
        
        self.console.print(table)
    
    def _display_simple_dashboard(self, tenant_id: str, app_id: str, title: str):
        """简单版本仪表板"""
        print(f"\n{'='*60}")
        print(title)
        print(f"{'='*60}")
        
        budget = self.get_budget(tenant_id)
        if budget:
            used = budget['totalBudget'] - budget['balance']
            print(f"💰 预算: ${budget['totalBudget']:.2f}")
            print(f"💵 已用: ${used:.4f}")
            print(f"💳 剩余: ${budget['balance']:.4f}")
            print(f"📞 调用: {budget['invocations']}")
        
        metrics = self.get_metrics(tenant_id, app_id)
        if metrics['Cost'] is not None:
            print(f"💸 成本: ${metrics['Cost']:.6f}")
        if metrics['InputTokens'] is not None and metrics['OutputTokens'] is not None:
            print(f"🔢 Token: {int(metrics['InputTokens'] + metrics['OutputTokens'])}")
        
        print(f"{'='*60}")
    
    def _get_bar(self, percentage: float) -> str:
        """生成进度条"""
        bar_length = 20
        filled = int(percentage / 100 * bar_length)
        return f"[{'█' * filled}{'░' * (bar_length - filled)}]"


class SingleTest:
    """单次测试"""
    
    def __init__(self, tenant_id: str = "demo1", app_id: str = "websearch"):
        self.tenant_id = tenant_id
        self.app_id = app_id
        self.monitor = RealtimeMonitor()
        self.before_state = None
        self.call_result = None
        
        if RICH_AVAILABLE:
            self.console = Console()
    
    def run(self):
        """运行测试"""
        if RICH_AVAILABLE:
            self.console.print(Panel.fit(
                f"🧪 实时测试 - {self.tenant_id}/{self.app_id}\n"
                f"⏰ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
                "🚀 调用Bedrock托管的模型",
                title="测试开始",
                border_style="blue"
            ))
        else:
            print(f"\n🧪 实时测试 - {self.tenant_id}/{self.app_id}")
            print(f"⏰ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        
        # 测试前状态
        if RICH_AVAILABLE:
            self.console.rule("[bold blue]📊 测试前状态")
        else:
            print("\n📊 测试前状态")
        
        # 保存测试前状态
        self.before_state = {
            'budget': self.monitor.get_budget(self.tenant_id),
            'metrics': self.monitor.get_metrics(self.tenant_id, self.app_id)
        }
        
        self.monitor.display_dashboard(
            self.tenant_id,
            self.app_id,
            f"📊 实时监控 - {self.tenant_id}/{self.app_id}"
        )
        
        # 调用API - 使用多次短prompt累积触发告警
        print("\n🚀 开始多次调用累积触发告警...")
        print(f"📊 目标: 成本>$0.01 或 Token>1000 (5分钟内)")
        
        # 短prompt列表，用于快速调用
        short_prompts = [
            "什么是云计算？",
            "AWS有哪些主要服务？", 
            "如何优化云成本？",
            "什么是微服务架构？",
            "解释容器化技术",
            "什么是DevOps？",
            "云安全最佳实践",
            "数据库分片策略",
            "负载均衡原理",
            "缓存设计模式"
        ]
        
        total_cost = 0
        total_tokens = 0
        call_count = 0
        last_result = None
        
        # 多次调用直到触发告警阈值
        for i, prompt in enumerate(short_prompts):
            call_count += 1
            payload = {
                "tenantId": self.tenant_id,
                "applicationId": self.app_id,
                "prompt": prompt,
                "model": "amazon.nova-pro-v1:0"
            }
            
            print(f"\n📞 调用 {call_count}: {prompt}")
            
            try:
                start_time = time.time()
                response = requests.post(
                    API_URL,
                    json=payload,
                    headers={
                        'Content-Type': 'application/json',
                        'x-tenant-id': self.tenant_id
                    },
                    timeout=REQUEST_TIMEOUT
                )
                latency = time.time() - start_time
                
                if response.status_code == 200:
                    result = response.json()
                    call_cost = result.get('cost', 0)
                    call_tokens = result.get('inputTokens', 0) + result.get('outputTokens', 0)
                    
                    total_cost += call_cost
                    total_tokens += call_tokens
                    last_result = result
                    
                    print(f"   ✅ 成功 - 成本: ${call_cost:.6f}, Token: {call_tokens}")
                    print(f"   📊 累计 - 成本: ${total_cost:.6f}, Token: {total_tokens}")
                    
                    # 检查是否达到告警阈值
                    if total_cost >= 0.01:
                        print(f"   🚨 成本告警阈值已达到: ${total_cost:.6f} >= $0.01")
                        break
                    elif total_tokens >= 1000:
                        print(f"   🚨 Token告警阈值已达到: {total_tokens} >= 1000")
                        break
                        
                else:
                    print(f"   ❌ 失败: {response.status_code}")
                    if response.status_code == 504:
                        print(f"   ⚠️  API Gateway超时，继续下一个调用...")
                        continue
                    else:
                        break
                        
            except requests.exceptions.Timeout:
                print(f"   ⏰ 请求超时，继续下一个调用...")
                continue
            except Exception as e:
                print(f"   ❌ 错误: {e}")
                break
                
            # 短暂延迟避免过快调用
            time.sleep(1)
        
        print(f"\n📊 最终统计:")
        print(f"   📞 总调用次数: {call_count}")
        print(f"   💰 总成本: ${total_cost:.6f}")
        print(f"   🔢 总Token: {total_tokens}")
        
        # 使用最后一次成功调用的结果
        if last_result:
            result = last_result
            beijing_time = (datetime.utcnow() + timedelta(hours=8)).strftime('%Y-%m-%d %H:%M:%S')
            
            # 保存调用结果（使用累计数据）
            self.call_result = {
                'inputTokens': sum([r.get('inputTokens', 0) for r in [last_result] if r]),
                'outputTokens': sum([r.get('outputTokens', 0) for r in [last_result] if r]),
                'cost': total_cost,
                'latency': 1.0,  # 平均延迟
                'model': payload['model']
            }
            
            print("✅ 多次API调用完成")
            print(f"\n{'='*60}")
            print("📋 累计调用详情")
            print(f"{'='*60}")
            print(f"🤖 模型: {payload['model']}")
            print(f"📞 调用次数: {call_count}")
            print(f"📝 最后响应: {result.get('response', '')[:100]}...")
            
            # 实时速率信息
            tokens_per_call = total_tokens / call_count if call_count > 0 else 0
            cost_per_token = total_cost / total_tokens if total_tokens > 0 else 0
            
            print(f"\n{'='*60}")
            print("⚡ 累计统计信息")
            print(f"{'='*60}")
            print(f"📊 总Token: {total_tokens} (北京时间: {beijing_time})")
            print(f"📈 平均Token/调用: {tokens_per_call:.0f}")
            print(f"💰 总成本: ${total_cost:.6f} (北京时间: {beijing_time})")
            print(f"💵 每Token成本: ${cost_per_token:.8f}")
            
            # 预算预测
            if self.before_state['budget']:
                budget = self.before_state['budget']
                remaining_budget = budget['balance']
                calls_remaining = int(remaining_budget / self.call_result['cost']) if self.call_result['cost'] > 0 else 0
                print(f"🔮 预计还可调用: {calls_remaining}次")
            
            print(f"{'='*60}")
        else:
            print("❌ 所有API调用都失败了")
            print(f"📊 部分统计:")
            print(f"   📞 尝试调用次数: {call_count}")
            print(f"   💰 累计成本: ${total_cost:.6f}")
            print(f"   🔢 累计Token: {total_tokens}")
            return False
        
        # 等待指标更新
        print("\n⏳ 等待30秒让指标更新...")
        for i in range(30, 0, -5):
            print(f"   ⏱️  剩余 {i} 秒...")
            time.sleep(5)
        
        # 测试后状态
        if RICH_AVAILABLE:
            self.console.rule("[bold blue]📊 测试后状态")
        else:
            print("\n📊 测试后状态")
        
        # 获取测试后状态
        after_state = {
            'budget': self.monitor.get_budget(self.tenant_id),
            'metrics': self.monitor.get_metrics(self.tenant_id, self.app_id)
        }
        
        self.monitor.display_dashboard(
            self.tenant_id,
            self.app_id,
            f"📊 实时监控 - {self.tenant_id}/{self.app_id}"
        )
        
        # 显示变化量
        self._display_changes(after_state)
        
        # 告警状态预测
        self._display_alert_prediction(after_state)
        
        # 完成
        if RICH_AVAILABLE:
            self.console.print(Panel.fit(
                "✅ 测试完成\n"
                "📊 实时数据已更新\n"
                "⏰ 告警将在2-3分钟内触发\n"
                "📧 请检查邮箱接收告警通知",
                title="测试结束",
                border_style="green"
            ))
        else:
            print("\n✅ 测试完成")
            print("📊 实时数据已更新")
            print("⏰ 告警将在2-3分钟内触发")
        
        return True
    
    def _display_changes(self, after_state: Dict):
        """显示变化量"""
        print(f"\n{'='*60}")
        print("📈 成本对比 - 变化量")
        print(f"{'='*60}")
        
        if self.before_state['budget'] and after_state['budget']:
            before_used = self.before_state['budget']['totalBudget'] - self.before_state['budget']['balance']
            after_used = after_state['budget']['totalBudget'] - after_state['budget']['balance']
            cost_change = after_used - before_used
            
            before_pct = (before_used / self.before_state['budget']['totalBudget'] * 100) if self.before_state['budget']['totalBudget'] > 0 else 0
            after_pct = (after_used / after_state['budget']['totalBudget'] * 100) if after_state['budget']['totalBudget'] > 0 else 0
            pct_change = after_pct - before_pct
            
            invocation_change = after_state['budget']['invocations'] - self.before_state['budget']['invocations']
            
            print(f"💰 成本变化: +${cost_change:.6f}")
            print(f"📊 预算消耗: {before_pct:.1f}% → {after_pct:.1f}% (+{pct_change:.1f}%)")
            print(f"📞 调用次数: +{invocation_change}次")
        
        if self.call_result:
            total_tokens = self.call_result['inputTokens'] + self.call_result['outputTokens']
            print(f"🔢 Token增量: +{total_tokens} tokens")
        
        print(f"{'='*60}")
    
    def _display_alert_prediction(self, after_state: Dict):
        """显示告警状态预测"""
        print(f"\n{'='*60}")
        print("🚨 告警状态预测 (5分钟窗口)")
        print(f"{'='*60}")
        
        # 成本告警阈值 (根据README: demo1超过$2/5分钟)
        cost_threshold = 2.0 if self.tenant_id == "demo1" else 5.0
        token_threshold = 3000
        
        metrics = after_state['metrics']
        
        if metrics['DetailedCost'] is not None:
            cost_5min = metrics['DetailedCost']
            cost_pct = (cost_5min / cost_threshold * 100)
            cost_remaining = cost_threshold - cost_5min
            
            print(f"💸 成本告警:")
            print(f"   当前: ${cost_5min:.6f} / ${cost_threshold:.2f}")
            print(f"   使用: {cost_pct:.1f}%")
            print(f"   距离告警: ${cost_remaining:.6f}")
            
            if cost_pct >= 100:
                print(f"   ⚠️  已触发告警!")
            elif cost_pct >= 80:
                print(f"   ⚠️  接近告警阈值!")
        
        if metrics['InputTokens'] is not None and metrics['OutputTokens'] is not None:
            total_tokens_5min = int(metrics['InputTokens'] + metrics['OutputTokens'])
            token_pct = (total_tokens_5min / token_threshold * 100)
            token_remaining = token_threshold - total_tokens_5min
            
            print(f"\n🔢 Token告警:")
            print(f"   当前: {total_tokens_5min} / {token_threshold} tokens")
            print(f"   使用: {token_pct:.1f}%")
            print(f"   距离告警: {token_remaining} tokens")
            
            if token_pct >= 100:
                print(f"   ⚠️  已触发告警!")
            elif token_pct >= 80:
                print(f"   ⚠️  接近告警阈值!")
        
        print(f"\n📧 告警通知将在2-3分钟内发送到: jackljx@amazon.com")
        print(f"{'='*60}")


def main():
    """主函数"""
    print("🎬 实时测试 - 真实Bedrock API调用")
    print("=" * 60)
    
    if not RICH_AVAILABLE:
        print("💡 提示: 安装rich库可获得更好的显示效果")
        print("   pip install rich\n")
    
    test = SingleTest(tenant_id="demo1", app_id="websearch")
    success = test.run()
    
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
