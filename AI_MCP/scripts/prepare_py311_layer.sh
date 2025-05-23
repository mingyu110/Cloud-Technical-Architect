#!/bin/bash
# prepare_py311_layer.sh
# 基于AI_MCP调试指南优化的Lambda Layer构建脚本
# 解决平台兼容性问题：确保为Linux x86_64环境构建正确的二进制文件

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 项目配置
PROJECT_ROOT=$(pwd)
LAYER_NAME="mcp-dependencies"
LAYER_BUILD_DIR="layer_build"
PYTHON_DIR="$LAYER_BUILD_DIR/python"
ZIP_FILE="py311_layer_linux.zip"
REQUIREMENTS_FILE="requirements.txt"

# AWS配置（可通过环境变量覆盖）
AWS_REGION=${AWS_REGION:-"us-east-1"}
LAMBDA_FUNCTIONS=("mcp-order-status-server" "mcp-client")

echo -e "${BLUE}🚀 AI_MCP Lambda Layer构建脚本${NC}"
echo -e "${BLUE}基于调试指南优化，解决平台兼容性问题${NC}"
echo ""

# 环境检查
echo -e "${YELLOW}📋 环境检查...${NC}"

# 检查必要工具
command -v python3 >/dev/null 2>&1 || { echo -e "${RED}❌ python3 未安装${NC}"; exit 1; }
command -v pip >/dev/null 2>&1 || { echo -e "${RED}❌ pip 未安装${NC}"; exit 1; }
command -v aws >/dev/null 2>&1 || { echo -e "${RED}❌ AWS CLI 未安装${NC}"; exit 1; }

# 检查requirements.txt
if [[ ! -f "$REQUIREMENTS_FILE" ]]; then
    echo -e "${RED}❌ 未找到 $REQUIREMENTS_FILE 文件${NC}"
    exit 1
fi

# 显示当前Python版本
PYTHON_VERSION=$(python3 --version)
echo -e "${GREEN}✅ Python: $PYTHON_VERSION${NC}"

# 显示pip版本
PIP_VERSION=$(pip --version)
echo -e "${GREEN}✅ pip: $PIP_VERSION${NC}"

# 检查AWS配置
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo -e "${RED}❌ AWS CLI 未配置或凭证无效${NC}"
    exit 1
fi
echo -e "${GREEN}✅ AWS CLI 已配置${NC}"

echo ""

# 清理旧构建
echo -e "${YELLOW}🧹 清理旧构建文件...${NC}"
rm -rf "$LAYER_BUILD_DIR"
rm -f "$ZIP_FILE"
echo -e "${GREEN}✅ 清理完成${NC}"

# 创建构建目录
echo -e "${YELLOW}📁 创建构建目录...${NC}"
mkdir -p "$PYTHON_DIR"
echo -e "${GREEN}✅ 构建目录创建完成: $PYTHON_DIR${NC}"

# 设置AWS分页器（避免shell配置冲突）
export AWS_PAGER=""

# 关键优化：为Lambda Linux x86_64环境构建依赖
echo -e "${YELLOW}📦 安装依赖包（Linux x86_64平台）...${NC}"
echo -e "${BLUE}解决方案：使用平台特定安装避免pydantic_core兼容性问题${NC}"

python3 -m pip install -r "$REQUIREMENTS_FILE" \
  -t "$PYTHON_DIR/" \
  --platform manylinux2014_x86_64 \
  --python-version 3.11 \
  --only-binary=:all: \
  --upgrade

if [[ $? -ne 0 ]]; then
    echo -e "${RED}❌ 依赖安装失败${NC}"
    exit 1
fi

echo -e "${GREEN}✅ 依赖安装完成${NC}"

# 验证关键二进制文件
echo -e "${YELLOW}🔍 验证关键二进制文件...${NC}"

# 检查pydantic_core（最常见的兼容性问题）
if [[ -d "$PYTHON_DIR/pydantic_core" ]]; then
    PYDANTIC_CORE_FILES=$(find "$PYTHON_DIR/pydantic_core" -name "_pydantic_core*.so" 2>/dev/null || true)
    if [[ -n "$PYDANTIC_CORE_FILES" ]]; then
        echo -e "${GREEN}✅ pydantic_core 二进制文件:${NC}"
        echo "$PYDANTIC_CORE_FILES" | while read -r file; do
            echo -e "   ${BLUE}$(basename "$file")${NC}"
        done
        
        # 验证是否为Linux版本
        if echo "$PYDANTIC_CORE_FILES" | grep -q "linux-gnu"; then
            echo -e "${GREEN}✅ 检测到正确的Linux二进制文件${NC}"
        elif echo "$PYDANTIC_CORE_FILES" | grep -q "darwin"; then
            echo -e "${RED}❌ 检测到macOS二进制文件，这将在Lambda中失败！${NC}"
            exit 1
        fi
    else
        echo -e "${YELLOW}⚠️ 未找到pydantic_core二进制文件${NC}"
    fi
else
    echo -e "${YELLOW}⚠️ 未找到pydantic_core目录${NC}"
fi

# 检查其他关键依赖
echo -e "${YELLOW}📋 验证其他关键依赖...${NC}"
REQUIRED_PACKAGES=("fastapi" "uvicorn" "mangum" "mcp" "boto3")

for package in "${REQUIRED_PACKAGES[@]}"; do
    if [[ -d "$PYTHON_DIR/$package" ]]; then
        echo -e "${GREEN}✅ $package${NC}"
    else
        echo -e "${RED}❌ 缺少 $package${NC}"
        exit 1
    fi
done

# 创建Layer ZIP文件
echo -e "${YELLOW}📦 创建Layer ZIP文件...${NC}"
cd "$LAYER_BUILD_DIR"
zip -r "../$ZIP_FILE" python/ >/dev/null

if [[ $? -ne 0 ]]; then
    echo -e "${RED}❌ ZIP文件创建失败${NC}"
    exit 1
fi

cd "$PROJECT_ROOT"
ZIP_SIZE=$(du -h "$ZIP_FILE" | cut -f1)
echo -e "${GREEN}✅ Layer ZIP创建完成: $ZIP_FILE ($ZIP_SIZE)${NC}"

# 上传Layer到AWS
echo -e "${YELLOW}☁️ 上传Layer到AWS Lambda...${NC}"

LAYER_RESULT=$(aws lambda publish-layer-version \
  --layer-name "$LAYER_NAME" \
  --zip-file "fileb://$ZIP_FILE" \
  --compatible-runtimes python3.11 \
  --region "$AWS_REGION" \
  --output json)

if [[ $? -ne 0 ]]; then
    echo -e "${RED}❌ Layer上传失败${NC}"
    exit 1
fi

LAYER_VERSION=$(echo "$LAYER_RESULT" | grep -o '"Version": [0-9]*' | grep -o '[0-9]*')
LAYER_ARN=$(echo "$LAYER_RESULT" | grep -o '"LayerArn": "[^"]*"' | sed 's/"LayerArn": "\([^"]*\)"/\1/')

echo -e "${GREEN}✅ Layer上传成功${NC}"
echo -e "${BLUE}   版本: $LAYER_VERSION${NC}"
echo -e "${BLUE}   ARN: $LAYER_ARN:$LAYER_VERSION${NC}"

# 更新Lambda函数使用新Layer
echo -e "${YELLOW}🔄 更新Lambda函数使用新Layer...${NC}"

for function_name in "${LAMBDA_FUNCTIONS[@]}"; do
    echo -e "${BLUE}更新函数: $function_name${NC}"
    
    UPDATE_RESULT=$(aws lambda update-function-configuration \
      --function-name "$function_name" \
      --layers "$LAYER_ARN:$LAYER_VERSION" \
      --region "$AWS_REGION" \
      --output json 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✅ $function_name 更新成功${NC}"
    else
        echo -e "${YELLOW}⚠️ $function_name 更新失败或函数不存在${NC}"
    fi
done

# 验证更新
echo -e "${YELLOW}🔍 验证Lambda函数Layer配置...${NC}"

for function_name in "${LAMBDA_FUNCTIONS[@]}"; do
    CURRENT_LAYER=$(aws lambda get-function-configuration \
      --function-name "$function_name" \
      --region "$AWS_REGION" \
      --query 'Layers[0].Arn' \
      --output text 2>/dev/null)
    
    if [[ "$CURRENT_LAYER" == "$LAYER_ARN:$LAYER_VERSION" ]]; then
        echo -e "${GREEN}✅ $function_name: 使用Layer版本 $LAYER_VERSION${NC}"
    elif [[ "$CURRENT_LAYER" != "None" && -n "$CURRENT_LAYER" ]]; then
        echo -e "${YELLOW}⚠️ $function_name: 使用不同的Layer版本${NC}"
        echo -e "   当前: $CURRENT_LAYER"
        echo -e "   期望: $LAYER_ARN:$LAYER_VERSION"
    else
        echo -e "${RED}❌ $function_name: 无法获取Layer信息${NC}"
    fi
done

# 清理本地文件
echo -e "${YELLOW}🧹 清理本地构建文件...${NC}"
if [[ "$1" != "--keep-build" ]]; then
    rm -rf "$LAYER_BUILD_DIR"
    rm -f "$ZIP_FILE"
    echo -e "${GREEN}✅ 本地构建文件已清理${NC}"
else
    echo -e "${BLUE}ℹ️ 保留本地构建文件（--keep-build选项）${NC}"
fi

echo ""
echo -e "${GREEN}🎉 Layer构建和部署完成！${NC}"
echo -e "${BLUE}📋 摘要:${NC}"
echo -e "   Layer名称: $LAYER_NAME"
echo -e "   版本: $LAYER_VERSION"
echo -e "   ARN: $LAYER_ARN:$LAYER_VERSION"
echo -e "   平台: Linux x86_64 (Lambda兼容)"
echo -e "   Python版本: 3.11"
echo ""

echo -e "${YELLOW}💡 使用提示:${NC}"
echo -e "   • 如果需要更新Terraform配置，请使用ARN: $LAYER_ARN:$LAYER_VERSION"
echo -e "   • 运行 './scripts/test_all_apis.sh' 验证功能是否正常"
echo -e "   • 查看CloudWatch日志确认无导入错误"
echo ""

echo -e "${GREEN}✅ 脚本执行完成${NC}" 