
from bedrock_agentcore.runtime import BedrockAgentCoreApp
from langchain_core.messages import HumanMessage
from langgraph.checkpoint.memory import MemorySaver

# 这是一个模拟的 deep_researcher_builder，以使代码可以独立运行。
# 在实际项目中，这里会导入真实的 LangChain 或 LangGraph 应用。
class MockDeepResearcher:
    def compile(self, checkpointer):
        return self

    async def astream(self, input_data, config, stream_mode):
        thread_id = config.get("configurable", {}).get("thread_id", "default_session")
        user_message = input_data.get("messages", [{}])[0].get("content", "No message")
        
        yield {
            "status": "received",
            "thread_id": thread_id,
            "input": user_message
        }
        yield {
            "status": "processing",
            "message": "Thinking about your request..."
        }
        yield {
            "status": "complete",
            "response": f"This is a mock response to: '{user_message}'"
        }

deep_researcher_builder = MockDeepResearcher()

# 初始化 Bedrock AgentCore 应用
app = BedrockAgentCoreApp()

# 编译 LangGraph 图，并配置内存检查点
graph = deep_researcher_builder.compile(checkpointer=MemorySaver())

@app.entrypoint
async def invoke_agent(request, context):
    """
    这是代理的入口点，由 Bedrock AgentCore Runtime 调用。
    它接收请求，调用 LangGraph，并流式返回结果。
    """
    user_msg = request.get("prompt", "No prompt found in input, please guide customer as to what tools can be used")

    # 异步调用 LangGraph，并流式传输事件
    stream = graph.astream(
        {
            "messages": [HumanMessage(content=user_msg)]
        },
        config={
            "configurable": {
                "thread_id": context.session_id,
            }
        },
        stream_mode="updates"
    )

    # 将 LangGraph 的事件流直接返回给调用者
    async for event in stream:
        yield event

if __name__ == "__main__":
    # 这使得应用可以在本地以开发模式运行
    app.run()
