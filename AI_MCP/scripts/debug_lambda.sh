#!/bin/bash
# debug_lambda.sh
# 基于AI_MCP调试指南的Lambda函数调试工具
# 快速诊断和修复常见问题

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
AWS_REGION=${AWS_REGION:-"us-east-1"}
LAMBDA_FUNCTIONS=("mcp-order-status-server" "mcp-client" "order_mock_api")
LAYER_NAME="mcp-dependencies"

echo -e "${BLUE}🔧 AI_MCP Lambda函数调试工具${NC}"
echo -e "${BLUE}基于调试指南的问题诊断和修复${NC}"
echo ""

# 设置AWS分页器
export AWS_PAGER=""

# 工具函数
check_aws_cli() {
    if ! command -v aws >/dev/null 2>&1; then
        echo -e "${RED}❌ AWS CLI 未安装${NC}"
        exit 1
    fi
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        echo -e "${RED}❌ AWS CLI 未配置或凭证无效${NC}"
        exit 1
    fi
}

get_latest_log_stream() {
    local function_name="$1"
    aws logs describe-log-streams \
        --log-group-name "/aws/lambda/$function_name" \
        --order-by LastEventTime \
        --descending \
        --max-items 1 \
        --query 'logStreams[0].logStreamName' \
        --output text 2>/dev/null || echo "NONE"
}

show_recent_logs() {
    local function_name="$1"
    local lines="${2:-20}"
    
    echo -e "${YELLOW}📋 查看 $function_name 最近的日志 (最近$lines行)...${NC}"
    
    local log_stream=$(get_latest_log_stream "$function_name")
    
    if [[ "$log_stream" == "NONE" || -z "$log_stream" ]]; then
        echo -e "${RED}❌ 未找到日志流，可能函数未执行过${NC}"
        return 1
    fi
    
    echo -e "${BLUE}   日志流: $log_stream${NC}"
    
    aws logs get-log-events \
        --log-group-name "/aws/lambda/$function_name" \
        --log-stream-name "$log_stream" \
        --limit "$lines" \
        --query 'events[*].[timestamp,message]' \
        --output table
}

check_function_config() {
    local function_name="$1"
    
    echo -e "${YELLOW}🔍 检查 $function_name 配置...${NC}"
    
    local config=$(aws lambda get-function-configuration \
        --function-name "$function_name" \
        --region "$AWS_REGION" \
        --output json 2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}❌ 无法获取函数配置，函数可能不存在${NC}"
        return 1
    fi
    
    # 基本信息
    local runtime=$(echo "$config" | jq -r '.Runtime')
    local state=$(echo "$config" | jq -r '.State')
    local last_modified=$(echo "$config" | jq -r '.LastModified')
    
    echo -e "${BLUE}   运行时: $runtime${NC}"
    echo -e "${BLUE}   状态: $state${NC}"
    echo -e "${BLUE}   最后修改: $last_modified${NC}"
    
    # Layer信息
    local layers=$(echo "$config" | jq -r '.Layers[]?.Arn // "无Layer"')
    echo -e "${BLUE}   Layers:${NC}"
    if [[ "$layers" == "无Layer" ]]; then
        echo -e "${RED}     ❌ 未配置Layer${NC}"
    else
        echo "$layers" | while read -r layer_arn; do
            echo -e "${GREEN}     ✅ $layer_arn${NC}"
        done
    fi
    
    # 环境变量
    local env_vars=$(echo "$config" | jq -r '.Environment.Variables // {} | to_entries[] | "\(.key)=\(.value)"')
    if [[ -n "$env_vars" ]]; then
        echo -e "${BLUE}   环境变量:${NC}"
        echo "$env_vars" | while read -r env_var; do
            echo -e "     ${BLUE}$env_var${NC}"
        done
    fi
    
    echo ""
}

check_layer_compatibility() {
    echo -e "${YELLOW}🔍 检查Layer兼容性问题...${NC}"
    
    local latest_layer=$(aws lambda list-layer-versions \
        --layer-name "$LAYER_NAME" \
        --max-items 1 \
        --query 'LayerVersions[0].Version' \
        --output text 2>/dev/null)
    
    if [[ "$latest_layer" == "None" || -z "$latest_layer" ]]; then
        echo -e "${RED}❌ 未找到Layer: $LAYER_NAME${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ 最新Layer版本: $latest_layer${NC}"
    
    # 检查每个函数使用的Layer版本
    for function_name in "${LAMBDA_FUNCTIONS[@]}"; do
        local current_layer=$(aws lambda get-function-configuration \
            --function-name "$function_name" \
            --region "$AWS_REGION" \
            --query 'Layers[0].Arn' \
            --output text 2>/dev/null)
        
        if [[ "$current_layer" == "None" || -z "$current_layer" ]]; then
            echo -e "${RED}❌ $function_name: 未配置Layer${NC}"
        elif [[ "$current_layer" == *":$latest_layer" ]]; then
            echo -e "${GREEN}✅ $function_name: 使用最新Layer版本 $latest_layer${NC}"
        else
            local current_version=$(echo "$current_layer" | grep -o '[0-9]*$')
            echo -e "${YELLOW}⚠️ $function_name: 使用旧版本 $current_version，最新版本: $latest_layer${NC}"
        fi
    done
}

search_error_logs() {
    local function_name="$1"
    local hours="${2:-1}"
    
    echo -e "${YELLOW}🔍 搜索 $function_name 错误日志 (最近${hours}小时)...${NC}"
    
    local start_time=$(date -d "$hours hours ago" +%s)000
    
    local errors=$(aws logs filter-log-events \
        --log-group-name "/aws/lambda/$function_name" \
        --filter-pattern "ERROR" \
        --start-time "$start_time" \
        --query 'events[*].message' \
        --output text 2>/dev/null)
    
    if [[ -z "$errors" ]]; then
        echo -e "${GREEN}✅ 未发现错误日志${NC}"
    else
        echo -e "${RED}❌ 发现错误:${NC}"
        echo "$errors" | head -10 | while read -r error; do
            echo -e "${RED}   $error${NC}"
        done
    fi
}

check_import_errors() {
    echo -e "${YELLOW}🔍 检查常见导入错误...${NC}"
    
    local common_import_errors=(
        "No module named 'fastapi'"
        "No module named 'pydantic'"
        "No module named 'pydantic_core'"
        "No module named 'mcp'"
        "_pydantic_core"
        "ImportModuleError"
    )
    
    for function_name in "${LAMBDA_FUNCTIONS[@]}"; do
        echo -e "${BLUE}检查 $function_name...${NC}"
        
        for error_pattern in "${common_import_errors[@]}"; do
            local found=$(aws logs filter-log-events \
                --log-group-name "/aws/lambda/$function_name" \
                --filter-pattern "$error_pattern" \
                --start-time $(date -d '24 hours ago' +%s)000 \
                --query 'events[0].message' \
                --output text 2>/dev/null)
            
            if [[ -n "$found" && "$found" != "None" ]]; then
                echo -e "${RED}   ❌ 发现导入错误: $error_pattern${NC}"
                echo -e "${RED}      $found${NC}"
            fi
        done
    done
}

fix_layer_issues() {
    echo -e "${YELLOW}🛠️ 修复Layer问题...${NC}"
    
    local latest_layer_arn=$(aws lambda list-layer-versions \
        --layer-name "$LAYER_NAME" \
        --max-items 1 \
        --query 'LayerVersions[0].LayerVersionArn' \
        --output text 2>/dev/null)
    
    if [[ "$latest_layer_arn" == "None" || -z "$latest_layer_arn" ]]; then
        echo -e "${RED}❌ 未找到可用的Layer版本${NC}"
        echo -e "${YELLOW}   建议运行: ./scripts/prepare_py311_layer.sh${NC}"
        return 1
    fi
    
    for function_name in "${LAMBDA_FUNCTIONS[@]}"; do
        echo -e "${BLUE}更新 $function_name 的Layer...${NC}"
        
        local result=$(aws lambda update-function-configuration \
            --function-name "$function_name" \
            --layers "$latest_layer_arn" \
            --region "$AWS_REGION" \
            --output json 2>/dev/null)
        
        if [[ $? -eq 0 ]]; then
            echo -e "${GREEN}✅ $function_name Layer更新成功${NC}"
        else
            echo -e "${RED}❌ $function_name Layer更新失败${NC}"
        fi
    done
}

check_bedrock_permissions() {
    echo -e "${YELLOW}🔍 检查Bedrock权限...${NC}"
    
    # 测试常用模型
    local models=(
        "amazon.titan-text-express-v1"
        "anthropic.claude-v2:1"
        "anthropic.claude-3-haiku-20240307-v1:0"
    )
    
    for model in "${models[@]}"; do
        echo -e "${BLUE}测试模型: $model${NC}"
        
        local test_result=$(aws bedrock-runtime invoke-model \
            --model-id "$model" \
            --body '{"inputText":"test","textGenerationConfig":{"maxTokenCount":1}}' \
            --region "$AWS_REGION" \
            /tmp/bedrock_test.json 2>&1)
        
        if [[ $? -eq 0 ]]; then
            echo -e "${GREEN}✅ $model: 有访问权限${NC}"
        elif echo "$test_result" | grep -q "AccessDeniedException"; then
            echo -e "${RED}❌ $model: 无访问权限${NC}"
            echo -e "${YELLOW}   需要在Bedrock控制台申请模型访问权限${NC}"
        else
            echo -e "${YELLOW}⚠️ $model: 测试失败（可能是请求格式问题）${NC}"
        fi
    done
    
    rm -f /tmp/bedrock_test.json
}

show_terraform_state() {
    echo -e "${YELLOW}🔍 检查Terraform状态同步...${NC}"
    
    if [[ ! -f "infrastructure/terraform/terraform.tfstate" ]]; then
        echo -e "${RED}❌ 未找到Terraform状态文件${NC}"
        return 1
    fi
    
    local tf_layer_version=$(grep -o '"mcp-dependencies:[0-9]*"' infrastructure/terraform/terraform.tfstate | head -1 | grep -o '[0-9]*')
    local actual_layer_version=$(aws lambda list-layer-versions \
        --layer-name "$LAYER_NAME" \
        --max-items 1 \
        --query 'LayerVersions[0].Version' \
        --output text 2>/dev/null)
    
    echo -e "${BLUE}   Terraform状态中的Layer版本: $tf_layer_version${NC}"
    echo -e "${BLUE}   AWS中的最新Layer版本: $actual_layer_version${NC}"
    
    if [[ "$tf_layer_version" != "$actual_layer_version" ]]; then
        echo -e "${YELLOW}⚠️ Terraform状态与实际资源不同步${NC}"
        echo -e "${YELLOW}   建议运行: terraform refresh${NC}"
    else
        echo -e "${GREEN}✅ Terraform状态与实际资源同步${NC}"
    fi
}

# 主菜单
show_menu() {
    echo -e "${BLUE}请选择操作:${NC}"
    echo "1. 检查所有函数配置"
    echo "2. 查看最近日志"
    echo "3. 搜索错误日志"
    echo "4. 检查Layer兼容性"
    echo "5. 检查导入错误"
    echo "6. 修复Layer问题"
    echo "7. 检查Bedrock权限"
    echo "8. 检查Terraform状态"
    echo "9. 完整诊断（推荐）"
    echo "0. 退出"
    echo ""
}

# 环境检查
check_aws_cli

# 主循环
while true; do
    show_menu
    read -p "请输入选择 (0-9): " choice
    echo ""
    
    case $choice in
        1)
            for function_name in "${LAMBDA_FUNCTIONS[@]}"; do
                check_function_config "$function_name"
            done
            ;;
        2)
            echo "选择函数:"
            for i in "${!LAMBDA_FUNCTIONS[@]}"; do
                echo "$((i+1)). ${LAMBDA_FUNCTIONS[i]}"
            done
            read -p "请输入函数编号: " func_num
            if [[ $func_num -ge 1 && $func_num -le ${#LAMBDA_FUNCTIONS[@]} ]]; then
                show_recent_logs "${LAMBDA_FUNCTIONS[$((func_num-1))]}"
            else
                echo -e "${RED}无效选择${NC}"
            fi
            ;;
        3)
            for function_name in "${LAMBDA_FUNCTIONS[@]}"; do
                search_error_logs "$function_name"
            done
            ;;
        4)
            check_layer_compatibility
            ;;
        5)
            check_import_errors
            ;;
        6)
            fix_layer_issues
            ;;
        7)
            check_bedrock_permissions
            ;;
        8)
            show_terraform_state
            ;;
        9)
            echo -e "${BLUE}🔍 执行完整诊断...${NC}"
            echo ""
            check_layer_compatibility
            echo ""
            check_import_errors
            echo ""
            for function_name in "${LAMBDA_FUNCTIONS[@]}"; do
                search_error_logs "$function_name"
            done
            echo ""
            check_bedrock_permissions
            echo ""
            show_terraform_state
            ;;
        0)
            echo -e "${GREEN}再见！${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选择，请重试${NC}"
            ;;
    esac
    
    echo ""
    read -p "按回车键继续..." 
    echo ""
done 