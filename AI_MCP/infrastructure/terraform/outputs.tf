output "mock_api_url" {
  description = "订单状态模拟API的URL"
  value       = module.order_mock_api_gateway.invoke_url
}

output "mcp_server_url" {
  description = "MCP服务器的URL"
  value       = module.mcp_server_api_gateway.invoke_url
}

output "chatbot_api_url" {
  description = "聊天机器人API的URL"
  value       = module.chatbot_api_gateway.invoke_url
} 