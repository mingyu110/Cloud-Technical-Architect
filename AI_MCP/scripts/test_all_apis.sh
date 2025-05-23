#!/bin/bash
# test_all_apis.sh
# 基于AI_MCP调试指南的全面API测试脚本
# 测试Mock API、MCP Server、Chatbot API的完整功能

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# API端点配置（从调试指南中的实际部署获取）
MOCK_API_URL="https://3kj9ouspqf.execute-api.us-east-1.amazonaws.com/dev"
MCP_SERVER_URL="https://1n6b8abkhi.execute-api.us-east-1.amazonaws.com/dev"
CHATBOT_API_URL="https://bqvhps1q81.execute-api.us-east-1.amazonaws.com/dev"

# 测试配置
TEST_ORDER_ID="12345"
TEST_QUERY="查询订单12345的状态"
TIMEOUT=30

echo -e "${BLUE}🧪 AI_MCP项目 - 全面API测试${NC}"
echo -e "${BLUE}基于调试指南的端到端验证流程${NC}"
echo ""

# 工具函数
check_curl() {
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${RED}❌ curl 未安装，请先安装curl${NC}"
        exit 1
    fi
}

check_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️ jq 未安装，JSON输出将不会格式化${NC}"
        return 1
    fi
    return 0
}

format_json() {
    if check_jq; then
        echo "$1" | jq .
    else
        echo "$1"
    fi
}

test_api() {
    local test_name="$1"
    local url="$2"
    local method="${3:-GET}"
    local data="$4"
    local expected_status="${5:-200}"
    
    echo -e "${YELLOW}🔍 测试: $test_name${NC}"
    echo -e "${BLUE}   URL: $url${NC}"
    
    if [[ "$method" == "POST" ]]; then
        response=$(curl -s -w "\n%{http_code}" -X POST "$url" \
            -H "Content-Type: application/json" \
            -d "$data" \
            --max-time $TIMEOUT)
    else
        response=$(curl -s -w "\n%{http_code}" "$url" \
            --max-time $TIMEOUT)
    fi
    
    # 分离响应体和状态码
    response_body=$(echo "$response" | head -n -1)
    status_code=$(echo "$response" | tail -n 1)
    
    echo -e "${BLUE}   状态码: $status_code${NC}"
    
    if [[ "$status_code" == "$expected_status" ]]; then
        echo -e "${GREEN}✅ HTTP状态码正确 ($status_code)${NC}"
    else
        echo -e "${RED}❌ HTTP状态码错误，期望: $expected_status，实际: $status_code${NC}"
        echo -e "${RED}响应内容:${NC}"
        echo "$response_body"
        return 1
    fi
    
    # 验证响应不为空
    if [[ -z "$response_body" ]]; then
        echo -e "${RED}❌ 响应内容为空${NC}"
        return 1
    fi
    
    # 尝试解析JSON
    if echo "$response_body" | jq . >/dev/null 2>&1; then
        echo -e "${GREEN}✅ 响应为有效JSON格式${NC}"
        echo -e "${BLUE}响应内容:${NC}"
        format_json "$response_body"
    else
        echo -e "${YELLOW}⚠️ 响应不是JSON格式${NC}"
        echo -e "${BLUE}响应内容:${NC}"
        echo "$response_body"
    fi
    
    echo ""
    return 0
}

# 环境检查
echo -e "${YELLOW}📋 环境检查...${NC}"
check_curl
check_jq
echo -e "${GREEN}✅ 环境检查完成${NC}"
echo ""

# 测试计数器
total_tests=0
passed_tests=0

# 测试1: Mock API - 订单状态查询
echo -e "${BLUE}=== 测试1: Mock API - 订单状态查询 ===${NC}"
total_tests=$((total_tests + 1))

if test_api "Mock API订单查询" \
    "$MOCK_API_URL/orders/$TEST_ORDER_ID" \
    "GET" \
    "" \
    "200"; then
    passed_tests=$((passed_tests + 1))
    echo -e "${GREEN}✅ Mock API测试通过${NC}"
else
    echo -e "${RED}❌ Mock API测试失败${NC}"
fi

echo ""

# 测试2: MCP Server - 健康检查
echo -e "${BLUE}=== 测试2: MCP Server - 健康检查 ===${NC}"
total_tests=$((total_tests + 1))

if test_api "MCP Server健康检查" \
    "$MCP_SERVER_URL/health" \
    "GET" \
    "" \
    "200"; then
    passed_tests=$((passed_tests + 1))
    echo -e "${GREEN}✅ MCP Server健康检查通过${NC}"
else
    echo -e "${RED}❌ MCP Server健康检查失败${NC}"
fi

echo ""

# 测试3: MCP Server - 工具调用
echo -e "${BLUE}=== 测试3: MCP Server - 工具调用 ===${NC}"
total_tests=$((total_tests + 1))

mcp_request='{
    "jsonrpc": "2.0",
    "id": "test-1",
    "method": "call_tool",
    "params": {
        "name": "get_order_status",
        "params": {"order_id": "'$TEST_ORDER_ID'"}
    }
}'

if test_api "MCP Server工具调用" \
    "$MCP_SERVER_URL/mcp" \
    "POST" \
    "$mcp_request" \
    "200"; then
    passed_tests=$((passed_tests + 1))
    echo -e "${GREEN}✅ MCP Server工具调用测试通过${NC}"
else
    echo -e "${RED}❌ MCP Server工具调用测试失败${NC}"
fi

echo ""

# 测试4: Chatbot API - 健康检查
echo -e "${BLUE}=== 测试4: Chatbot API - 健康检查 ===${NC}"
total_tests=$((total_tests + 1))

if test_api "Chatbot API健康检查" \
    "$CHATBOT_API_URL/health" \
    "GET" \
    "" \
    "200"; then
    passed_tests=$((passed_tests + 1))
    echo -e "${GREEN}✅ Chatbot API健康检查通过${NC}"
else
    echo -e "${RED}❌ Chatbot API健康检查失败${NC}"
fi

echo ""

# 测试5: Chatbot API - AI对话
echo -e "${BLUE}=== 测试5: Chatbot API - AI对话 ===${NC}"
total_tests=$((total_tests + 1))

chatbot_request='{
    "query": "'$TEST_QUERY'"
}'

if test_api "Chatbot AI对话" \
    "$CHATBOT_API_URL/chat" \
    "POST" \
    "$chatbot_request" \
    "200"; then
    passed_tests=$((passed_tests + 1))
    echo -e "${GREEN}✅ Chatbot AI对话测试通过${NC}"
else
    echo -e "${RED}❌ Chatbot AI对话测试失败${NC}"
fi

echo ""

# 高级验证测试
echo -e "${BLUE}=== 高级验证测试 ===${NC}"

# 测试6: 验证MCP Server返回正确的JSON-RPC格式
echo -e "${YELLOW}🔍 验证MCP Server JSON-RPC响应格式...${NC}"
total_tests=$((total_tests + 1))

mcp_response=$(curl -s -X POST "$MCP_SERVER_URL/mcp" \
    -H "Content-Type: application/json" \
    -d "$mcp_request" \
    --max-time $TIMEOUT)

if echo "$mcp_response" | jq -e '.jsonrpc == "2.0" and .id == "test-1" and .result' >/dev/null 2>&1; then
    echo -e "${GREEN}✅ MCP Server返回正确的JSON-RPC格式${NC}"
    passed_tests=$((passed_tests + 1))
else
    echo -e "${RED}❌ MCP Server JSON-RPC格式验证失败${NC}"
    echo -e "${RED}响应: $mcp_response${NC}"
fi

# 测试7: 验证Chatbot返回中文响应（UTF-8编码）
echo -e "${YELLOW}🔍 验证Chatbot中文响应编码...${NC}"
total_tests=$((total_tests + 1))

chatbot_response=$(curl -s -X POST "$CHATBOT_API_URL/chat" \
    -H "Content-Type: application/json" \
    -d "$chatbot_request" \
    --max-time $TIMEOUT)

if echo "$chatbot_response" | jq -e '.response' >/dev/null 2>&1; then
    response_text=$(echo "$chatbot_response" | jq -r '.response')
    if [[ "$response_text" != *"\\u"* ]]; then
        echo -e "${GREEN}✅ Chatbot返回正确的UTF-8编码响应${NC}"
        passed_tests=$((passed_tests + 1))
    else
        echo -e "${RED}❌ Chatbot响应包含Unicode转义字符${NC}"
        echo -e "${RED}响应: $response_text${NC}"
    fi
else
    echo -e "${RED}❌ Chatbot响应格式验证失败${NC}"
fi

echo ""

# 性能测试
echo -e "${BLUE}=== 性能验证 ===${NC}"

# 测试8: API响应时间
echo -e "${YELLOW}🔍 测试API响应时间...${NC}"
total_tests=$((total_tests + 1))

start_time=$(date +%s%N)
curl -s "$MOCK_API_URL/orders/$TEST_ORDER_ID" >/dev/null
end_time=$(date +%s%N)
response_time=$(( (end_time - start_time) / 1000000 ))

if [[ $response_time -lt 5000 ]]; then  # 5秒阈值
    echo -e "${GREEN}✅ API响应时间良好: ${response_time}ms${NC}"
    passed_tests=$((passed_tests + 1))
else
    echo -e "${YELLOW}⚠️ API响应时间较慢: ${response_time}ms${NC}"
fi

echo ""

# 结果摘要
echo -e "${BLUE}=== 测试结果摘要 ===${NC}"
echo -e "${BLUE}总测试数: $total_tests${NC}"
echo -e "${GREEN}通过测试: $passed_tests${NC}"
echo -e "${RED}失败测试: $((total_tests - passed_tests))${NC}"

success_rate=$(( passed_tests * 100 / total_tests ))
echo -e "${BLUE}成功率: $success_rate%${NC}"

if [[ $passed_tests -eq $total_tests ]]; then
    echo -e "${GREEN}🎉 所有测试通过！系统运行正常${NC}"
    exit 0
elif [[ $success_rate -ge 80 ]]; then
    echo -e "${YELLOW}⚠️ 大部分测试通过，但有部分问题需要关注${NC}"
    exit 1
else
    echo -e "${RED}❌ 多个测试失败，系统存在严重问题${NC}"
    exit 1
fi 