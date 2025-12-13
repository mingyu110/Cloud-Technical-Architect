#!/bin/bash

# Amazon Bedrock 多租户成本追踪系统 - API Gateway 5xx 错误排查脚本
# 功能：诊断 API Gateway 5xx 错误、Lambda 超时、集成配置等问题
# 用法：./troubleshoot_apigateway.sh [api_id] [region]

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查依赖
command -v aws >/dev/null 2>&1 || { echo -e "${RED}❌ 请先安装 AWS CLI${NC}"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo -e "${RED}❌ 请先安装 curl${NC}"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo -e "${RED}❌ 请先安装 jq${NC}"; exit 1; }

# 参数配置
REGION="${2:-us-east-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
STACK_NAME="bedrock-cost-tracking"

if [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ 无法获取 AWS 账户 ID，请检查 AWS CLI 配置${NC}"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}API Gateway 5xx 错误排查脚本${NC}"
echo -e "${BLUE}区域: $REGION${NC}"
echo -e "${BLUE}账户: $ACCOUNT_ID${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 获取 API Gateway 信息
echo -e "${YELLOW}🔍 获取 API Gateway 配置信息${NC}"

# 尝试从 CloudFormation 获取 API ID
API_ID=$(aws cloudformation describe-stack-resources \
    --stack-name "${STACK_NAME}-apigateway" \
    --region $REGION \
    --query 'StackResources[?ResourceType==`AWS::ApiGateway::RestApi`].PhysicalResourceId' \
    --output text 2>/dev/null || echo "")

if [ -z "$API_ID" ]; then
    # 用户提供的 API ID
    API_ID="${1:-}"
    if [ -z "$API_ID" ]; then
        echo -e "${RED}❌ 无法获取 API Gateway ID${NC}"
        echo "请提供参数: ./troubleshoot_apigateway.sh [api_id] [region]"
        echo "或确保 CloudFormation 堆栈存在: ${STACK_NAME}-apigateway"
        exit 1
    fi
fi

echo "API Gateway ID: $API_ID"

# 获取 API 详情
API_DETAILS=$(aws apigateway get-rest-api --rest-api-id "$API_ID" --region $REGION --output json 2>/dev/null)
if [ $? -eq 0 ]; then
    API_NAME=$(echo "$API_DETAILS" | jq -r '.name')
    API_DESC=$(echo "$API_DETAILS" | jq -r '.description // "No description"')
    API_CREATED=$(echo "$API_DETAILS" | jq -r '.createdDate')
    echo -e "${GREEN}✅ API 存在: $API_NAME${NC}"
    echo "描述: $API_DESC"
    echo "创建时间: $API_CREATED"
else
    echo -e "${RED}❌ 无法获取 API Gateway 详情${NC}"
    exit 1
fi
echo ""

# 1. 检查 API Gateway 部署
echo -e "${YELLOW}🔍 步骤 1: 检查 API Gateway 部署状态${NC}"
echo "检查部署状态和阶段..."

# 获取部署信息
aws apigateway get-deployments --rest-api-id "$API_ID" --region $REGION --query 'items[0:5].[id,createdDate]' --output table 2>/dev/null || echo -e "${RED}❌ 无法获取部署信息${NC}"

# 获取阶段信息
STAGES=$(aws apigateway get-stages --rest-api-id "$API_ID" --region $REGION --output json 2>/dev/null)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ 阶段配置:${NC}"
    echo "$STAGES" | jq -r '.item[] | {stageName: .stageName, deploymentId: .deploymentId, createdDate: .createdDate}'
else
    echo -e "${RED}❌ 无法获取阶段信息${NC}"
fi
echo ""

# 2. 检查 Lambda 集成配置
echo -e "${YELLOW}🔍 步骤 2: 检查 Lambda 集成配置${NC}"
echo "验证 API Gateway 与 Lambda 的集成..."

# 获取资源和方法
RESOURCES=$(aws apigateway get-resources --rest-api-id "$API_ID" --region $REGION --output json 2>/dev/null)
if [ $? -eq 0 ]; then
    echo "资源和方法:"
    echo "$RESOURCES" | jq -r '.items[] | {id: .id, path: .path, methods: .resourceMethods // {} | keys}' | head -5

    # 查找 POST 方法
    INVOKE_RESOURCE_ID=$(echo "$RESOURCES" | jq -r '.items[] | select(.path=="/invoke") | .id' 2>/dev/null)

    if [ -n "$INVOKE_RESOURCE_ID" ]; then
        echo -e "${GREEN}✅ 找到 /invoke 资源: $INVOKE_RESOURCE_ID${NC}"

        # 获取方法集成配置
        INTEGRATION_CONFIG=$(aws apigateway get-integration \
            --rest-api-id "$API_ID" \
            --resource-id "$INVOKE_RESOURCE_ID" \
            --http-method POST \
            --region $REGION \
            --output json 2>/dev/null)

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ POST 方法集成配置:${NC}"
            echo "$INTEGRATION_CONFIG" | jq '{type: .type,uri: .uri,integrationHttpMethod: .httpMethod,passthroughBehavior: .passthroughBehavior}'

            LAMBDA_URI=$(echo "$INTEGRATION_CONFIG" | jq -r '.uri // ""
            if [ -n "$LAMBDA_URI" ]; then
                echo "Lambda 函数 URI: $LAMBDA_URI"
            fi
        else
            echo -e "${RED}❌ 无法获取 POST 方法集成配置${NC}"
        fi
    else
        echo -e "${RED}❌ 未找到 /invoke 资源${NC}"
    fi
else
    echo -e "${RED}❌ 无法获取资源列表${NC}"
fi
echo ""

# 3. 检查 Lambda 函数状态
echo -e "${YELLOW}🔍 步骤 3: 检查 Lambda 函数状态${NC}"
echo "验证主 Lambda 函数配置..."

MAIN_LAMBDA_FUNC="bedrock-main-function"
LAMBDA_CONFIG=$(aws lambda get-function-configuration --function-name "$MAIN_LAMBDA_FUNC" --region $REGION --output json 2>/dev/null)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Lambda 函数配置:${NC}"
    FUNCTION_NAME=$(echo "$LAMBDA_CONFIG" | jq -r '.FunctionName')
    STATE=$(echo "$LAMBDA_CONFIG" | jq -r '.State')
    TIMEOUT=$(echo "$LAMBDA_CONFIG" | jq -r '.Timeout')
    MEMORY=$(echo "$LAMBDA_CONFIG" | jq -r '.MemorySize')

    echo "函数名: $FUNCTION_NAME"
    echo "状态: $STATE"
    echo "超时时间: ${TIMEOUT} 秒"
    echo "内存: ${MEMORY} MB"

    if [ "$STATE" != "Active" ]; then
        echo -e "${RED}⚠️  Lambda 函数状态不是 'Active': $STATE${NC}"
    fi

    # 检查并发设置
    CONCURRENT_EXEC=$(echo "$LAMBDA_CONFIG" | jq -r '.ConcurrentExecutions // "未设置"')
    echo "并发执行数限制: $CONCURRENT_EXEC"

    # 检查超时设置
    if [ "$TIMEOUT" -lt 30 ]; then
        echo -e "${RED}⚠️  Lambda 超时时间较短 (${TIMEOUT}s)，Bedrock 调用可能需要更长时间${NC}"
        echo "建议设置: 30 秒或更长"
    fi
else
    echo -e "${RED}❌ 无法获取 Lambda 函数配置${NC}"
fi
echo ""

# 4. 检查 Lambda 权限
echo -e "${YELLOW}🔍 步骤 4: 检查 Lambda 权限配置${NC}"
echo "验证 API Gateway 是否有权限调用 Lambda..."

# 检查 Lambda 函数策略
LAMBDA_POLICY=$(aws lambda get-policy --function-name "$MAIN_LAMBDA_FUNC" --region $REGION --output json 2>/dev/null)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Lambda 函数策略已配置${NC}"

    # 解析策略
    STATEMENTS=$(echo "$LAMBDA_POLICY" | jq -r '.Policy' | jq -r '.Statement | length')
    echo "策略语句数量: $STATEMENTS"

    # 检查是否有 API Gateway 权限
    if echo "$LAMBDA_POLICY" | jq -r '.Policy' | jq -e '.Statement[] | select(.Principal.Service == "apigateway.amazonaws.com")' > /dev/null; then
        echo -e "${GREEN}✅ 包含 API Gateway 调用权限${NC}"
    else
        echo -e "${YELLOW}⚠️  可能缺少 API Gateway 调用权限${NC}"
    fi
else
    echo -e "${RED}❌ Lambda 函数没有配置策略${NC}"
    echo "需要使用 add-permission 命令添加权限"
fi
echo ""

# 5. 测试直接 Lambda 调用
echo -e "${YELLOW}🔍 步骤 5: 测试直接 Lambda 调用${NC}"
echo "绕过 API Gateway，直接调用 Lambda 函数..."

TEST_PAYLOAD=$(cat <<'EOF'
{
    "tenantId": "tenant-demo1",
    "applicationId": "test-troubleshoot",
    "model": "claude-3-haiku",
    "prompt": "Test connectivity",
    "maxTokens": 10
}
EOF
)

echo "测试负载:"
echo "$TEST_PAYLOAD" | jq .

echo ""
echo "调用 Lambda 函数 (最长等待 30 秒)..."

RESPONSE_FILE="/tmp/lambda_test_response.json"
START_TIME=$(date +%s)

aws lambda invoke \
    --function-name "$MAIN_LAMBDA_FUNC" \
    --payload "$TEST_PAYLOAD" \
    --cli-binary-format raw-in-base64-out \
    --region $REGION \
    "$RESPONSE_FILE" \
    --cli-read-timeout 30 \
    --output json > /tmp/invoke_info.json 2>1

INVOKE_EXIT_CODE=$?
END_TIME=$(date +%s)
EXECUTION_TIME=$((END_TIME - START_TIME))

if [ $INVOKE_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✅ Lambda 函数调用成功${NC}"
    echo "执行时间: ${EXECUTION_TIME} 秒"

    # 输出响应信息
    STATUS_CODE=$(cat /tmp/invoke_info.json | jq -r '.StatusCode // "N/A"')
    EXEC_RESULT=$(cat /tmp/invoke_info.json | jq -r '.ExecutionResult // "N/A"')

    echo "HTTP 状态码: $STATUS_CODE"
    echo "执行结果: $EXEC_RESULT"

    # 显示响应内容
    if [ -f "$RESPONSE_FILE" ]; then
        echo "响应内容:"
        if cat "$RESPONSE_FILE" | jq . > /dev/null 2>&1; then
            cat "$RESPONSE_FILE" | jq .
        else
            echo "原始响应:"
            cat "$RESPONSE_FILE"
        fi
    fi

    # 检查执行时间
    if [ "$EXECUTION_TIME" -gt 25 ]; then
        echo -e "${YELLOW}⚠️  Lambda 执行时间较长，可能在 API Gateway 超时之前未完成${NC}"
    fi
else
    echo -e "${RED}❌ Lambda 函数调用失败${NC}"
    echo "错误信息:"
    cat /tmp/invoke_info.json || echo "Lambda 调用失败（超时或错误）"
fi
echo ""

# 6. 检查 API Gateway 日志
echo -e "${YELLOW}🔍 步骤 6: 检查 API Gateway 日志${NC}"
echo "获取 API Gateway 执行日志..."

# API Gateway 执行日志组
API_LOG_GROUP="API-Gateway-Execution-Logs_${API_ID}/prod"

if aws logs describe-log-groups --log-group-name-prefix "$API_LOG_GROUP" --region $REGION | grep -q "$API_LOG_GROUP"; then
    echo -e "${GREEN}✅ 找到 API Gateway 日志组: $API_LOG_GROUP${NC}"

    # 检查最近的 5xx 错误
    echo "最近的 5xx 错误:"
    aws logs filter-log-events \
        --log-group-name "$API_LOG_GROUP" \
        --filter-pattern '"[ERROR]" OR "5"' \
        --region $REGION \
        --limit 5 \
        --query 'events[0:5].{timestamp:fromtimestamp(@.timestamp/1000),message:@.message}' \
        --output table 2>/dev/null || echo -e "${YELLOW}ℹ️  未找到 5xx 错误日志${NC}"

    echo -e "\n最近的执行日志:"
    aws logs filter-log-events \
        --log-group-name "$API_LOG_GROUP" \
        --region $REGION \
        --limit 5 \
        --query 'events[0:5].{timestamp:fromtimestamp(@.timestamp/1000),message:@.message}' \
        --output table 2>/dev/null | head -10

else
    echo -e "${YELLOW}⚠️  未找到 API Gateway 执行日志组${NC}"
    echo "可能原因："
    echo "1. API Gateway 日志未启用"
    echo "2. 日志记录级别设置不正确"
    echo "3. 此阶段尚未被调用"
fi
echo ""

# 7. 检查 API Gateway 监控指标
echo -e "${YELLOW}🔍 步骤 7: 检查 API Gateway CloudWatch 指标${NC}"
echo "获取 API Gateway 的 4xx/5xx 错误指标..."

# 查询最近 1 小时的错误指标
START_TIME=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)
END_TIME=$(date -u +%Y-%m-%dT%H:%M:%S)

echo "4xx 错误 (ClientError):"
aws cloudwatch get-metric-statistics \
    --namespace "AWS/ApiGateway" \
    --metric-name "4XXError" \
    --dimensions Name=ApiName,Value="$API_NAME" Name=Stage,Value=prod \
    --start-time "$START_TIME" \
    --end-time "$END_TIME" \
    --period 300 \
    --statistics Sum \
    --region $REGION \
    --query 'Datapoints[0:5].{Time:Timestamp,Count:Sum}' \
    --output table 2>/dev/null || echo "无 4xx 错误数据"

echo -e "\n5xx 错误 (ServerError):"
aws cloudwatch get-metric-statistics \
    --namespace "AWS/ApiGateway" \
    --metric-name "5XXError" \
    --dimensions Name=ApiName,Value="$API_NAME" Name=Stage,Value=prod \
    --start-time "$START_TIME" \
    --end-time "$END_TIME" \
    --period 300 \
    --statistics Sum \
    --region $REGION \
    --query 'Datapoints[0:5].{Time:Timestamp,Count:Sum}' \
    --output table 2>/dev/null || echo "无 5xx 错误数据"

echo -e "\n请求延迟 (Latency):"
aws cloudwatch get-metric-statistics \
    --namespace "AWS/ApiGateway" \
    --metric-name "Latency" \
    --dimensions Name=ApiName,Value="$API_NAME" Name=Stage,Value=prod \
    --start-time "$START_TIME" \
    --end-time "$END_TIME" \
    --period 300 \
    --statistics Average \
    --region $REGION \
    --query 'Datapoints[0:3].{Time:Timestamp,Latency:Average}' \
    --output table 2>/dev/null || echo "无延迟数据"
echo ""

# 8.测试 API Gateway 调用
echo -e "${YELLOW}🔍 步骤 8: 测试 API Gateway 调用${NC}"
echo "通过 API Gateway 调用以重现问题..."

# 获取 API 端点
API_ENDPOINT="https://${API_ID}.execute-api.${REGION}.amazonaws.com/prod/invoke"

echo "API 端点: $API_ENDPOINT"
echo "发送测试请求..."

# 发送请求并捕获响应
RESPONSE_FILE="/tmp/api_test_response.json"
HTTP_CODE=$(curl -s -o "$RESPONSE_FILE" -w "%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "X-Tenant-Id: tenant-demo1" \
    -d '{
        "applicationId": "troubleshoot-test",
        "model": "claude-3-haiku",
        "prompt": "Hello, API Gateway!",
        "maxTokens": 50
    }' \
    --max-time 35 \
    "$API_ENDPOINT")

echo "HTTP 响应码: $HTTP_CODE"

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
    echo -e "${GREEN}✅ API 调用成功${NC}"
    echo "响应内容:"
    if cat "$RESPONSE_FILE" | jq . > /dev/null 2>&1; then
        cat "$RESPONSE_FILE" | jq .
    else
        echo "原始响应:"
        cat "$RESPONSE_FILE"
    fi
else
    echo -e "${RED}❌ API 调用失败${NC}"
    echo "响应内容:"
    cat "$RESPONSE_FILE"
echo ""

# 9. 检查 Lambda 冷启动和内存
echo -e "${YELLOW}🔍 步骤 9: 检查 Lambda 性能配置${NC}"
echo "检查可能导致超时的因素..."

LAMBDA_METRICS_START=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)
LAMBDA_METRICS_END=$(date -u +%Y-%m-%dT%H:%M:%S)

echo "Lambda MemoryUtilization:"
aws cloudwatch get-metric-statistics \
    --namespace "AWS/Lambda" \
    --metric-name "MemoryUtilization" \
    --dimensions Name=FunctionName,Value="$MAIN_LAMBDA_FUNC" \
    --start-time "$LAMBDA_METRICS_START" \
    --end-time "$LAMBDA_METRICS_END" \
    --period 300 \
    --statistics Average \
    --region $REGION \
    --query 'Datapoints[0:3].{Time:Timestamp,Memory:Average}' \
    --output table 2>/dev/null || echo "无内存利用率数据"

echo -e "\nLambda Duration:"
aws cloudwatch get-metric-statistics \
    --namespace "AWS/Lambda" \
    --metric-name "Duration" \
    --dimensions Name=FunctionName,Value="$MAIN_LAMBDA_FUNC" \
    --start-time "$LAMBDA_METRICS_START" \
    --end-time "$LAMBDA_METRICS_END" \
    --period 300 \
    --statistics Average \
    --region $REGION \
    --query 'Datapoints[0:3].{Time:Timestamp,Duration:Average}' \
    --output table 2>/dev/null || echo "无持续时长数据"
echo ""

# 总结
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}API Gateway 5xx 错误排查总结${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "常见 5xx 错误原因:"
echo "1. ❌ 502 Bad Gateway - Lambda 函数出错或返回格式错误"
echo "2. ❌ 503 Service Unavailable - Lambda 函数限流或不可用"
echo "3. ❌ 504 Gateway Timeout - Lambda 函数执行时间超过 API Gateway 超时时间"
echo ""
echo -e "${YELLOW}推荐解决方案:${NC}"
echo "1. 检查 Lambda 函数是否有适当的错误处理"
echo "2. 确保 Lambda 函数在 29 秒内完成执行"
echo "3. 验证 Lambda 函数返回正确的 JSON 格式"
echo "4. 检查 Lambda 函数是否有足够的内存和并发"
echo "5. 确保 Lambda 函数有正确的 IAM 权限"
echo "6. 启用 API Gateway 日志记录以获取详细的错误信息"
echo ""

# 快速修复命令
echo -e "${YELLOW}快速修复命令建议:${NC}"
echo "# 增加 Lambda 超时时间"
echo "aws lambda update-function-configuration --function-name $MAIN_LAMBDA_FUNC --timeout 30 --region $REGION"
echo ""
echo "# 增加 Lambda 内存"
echo "aws lambda update-function-configuration --function-name $MAIN_LAMBDA_FUNC --memory-size 1024 --region $REGION"
echo ""
echo "# 确保 Lambda 权限"
echo "aws lambda add-permission --function-name $MAIN_LAMBDA_FUNC --statement-id apigateway-invoke --action lambda:InvokeFunction --principal apigateway.amazonaws.com --source-arn \"arn:aws:execute-api:$REGION:$ACCOUNT_ID:$API_ID/*/POST/invoke\" --region $REGION"
echo ""

# 清理临时文件
rm -f /tmp/lambda_test_response.json /tmp/invoke_info.json /tmp/api_test_response.json

echo -e "${GREEN}✅ 排查完成！${NC}"
echo "如需进一步帮助，请提供上述输出的详细信息，特别是："
echo "- API Gateway ID"
echo "- 具体的错误响应码"
echo "- Lambda 函数状态和配置"