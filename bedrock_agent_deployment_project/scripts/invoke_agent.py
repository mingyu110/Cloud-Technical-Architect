

import boto3
import json
import uuid
import os
import sys

# 从环境变量加载配置，如果失败则提供清晰的指导
def get_required_env(key):
    value = os.getenv(key)
    if not value:
        print(f"错误: 环境变量 {key} 未设置。", file=sys.stderr)
        print(f"请在 .env 文件中或在您的环境中设置此变量。", file=sys.stderr)
        sys.exit(1)
    return value

# --- 配置 ---
# 从环境变量中安全地读取配置
aws_account_id = get_required_env('AWS_ACCOUNT_ID')
aws_region = get_required_env('AWS_REGION')
agentcore_id = get_required_env('AGENTCORE_ID')
# --- 结束配置 ---

# 构造代理的 ARN (Amazon Resource Name)
agent_runtime_arn = f"arn:aws:bedrock-agentcore:{aws_region}:{aws_account_id}:runtime/{agentcore_id}"

# 初始化 boto3 客户端
client = boto3.client('bedrock-agentcore', region_name=aws_region)

# 为本次交互创建一个唯一的会话 ID
session_id = f'cli-session-{uuid.uuid4().hex}'

print(f"正在连接到代理: {agent_runtime_arn}")
print(f"会话 ID: {session_id}")
print("输入您的提示，按 Enter 发送。按 CTRL+C 退出。")

try:
    while True:
        prompt = input("\n提示 > ")
        if not prompt.strip():
            continue
            
        try:
            # 调用已部署的 AgentCore 运行时
            response = client.invoke_agent_runtime(
                agentRuntimeArn=agent_runtime_arn,
                qualifier="DEFAULT",  # 使用默认版本
                runtimeSessionId=session_id,
                payload=json.dumps({"prompt": prompt}).encode() 
            )

            # 处理流式响应
            if "text/event-stream" in response.get("contentType", ""):
                print("代理响应 (流式):\n" + "-"*20)
                full_response = []
                for line in response["response"].iter_lines(chunk_size=10):
                    if line:
                        line_str = line.decode("utf-8")
                        if line_str.startswith("data: "):
                            data_chunk = line_str[6:]
                            print(data_chunk) # 实时打印每个数据块
                            full_response.append(data_chunk)
                print("-"*20 + "\n流式传输结束。")

            # 处理标准的 JSON 响应
            elif response.get("contentType") == "application/json":
                content = response["response"].read().decode('utf-8')
                print("代理响应 (JSON):", json.loads(content))
            
            # 处理其他未知的响应类型
            else:
                print("收到未知响应类型:", response)

        except Exception as e:
            print(f"调用代理时出错: {e}", file=sys.stderr)
            
except KeyboardInterrupt:
    print("\n再见!")

