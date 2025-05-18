#!/bin/bash
set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 创建临时目录
TEMP_DIR=$(mktemp -d)
PYTHON_DIR="$TEMP_DIR/python"
mkdir -p "$PYTHON_DIR"

echo -e "${BLUE}===== 开始准备Lambda Layer依赖 =====${NC}"
echo -e "${BLUE}临时目录: $TEMP_DIR${NC}"

# 安装依赖
echo -e "${BLUE}安装项目依赖...${NC}"
echo -e "${BLUE}将安装以下依赖:${NC}"
echo "boto3>=1.28.0"
echo "requests>=2.31.0"
echo "fastmcp>=2.0"
echo "pytest>=7.4.0"
echo "pydantic==2.5.3"
echo "pydantic-core==2.14.5"

pip install boto3>=1.28.0 requests>=2.31.0 fastmcp>=2.0 pytest>=7.4.0 pydantic==2.5.3 pydantic-core==2.14.5 -t "$PYTHON_DIR"
echo -e "${GREEN}依赖安装完成！${NC}"

# 打包为ZIP
ZIP_FILE="$TEMP_DIR/layer.zip"
echo -e "${BLUE}创建ZIP文件: $ZIP_FILE${NC}"
cd "$TEMP_DIR" && zip -r layer.zip python

echo -e "${BLUE}检查ZIP文件内容:${NC}"
unzip -l "$ZIP_FILE" | grep -i "pydantic"

echo -e "${GREEN}===== Layer依赖已准备完成 =====${NC}"
echo -e "${GREEN}ZIP文件位置: $ZIP_FILE${NC}"
echo -e "${YELLOW}现在您可以登录AWS控制台，创建Lambda Layer:${NC}"
echo -e "1. 登录AWS管理控制台，进入Lambda服务"
echo -e "2. 在左侧导航栏选择\"Layers\""
echo -e "3. 点击\"Create layer\"按钮"
echo -e "4. 填写Layer信息，上传ZIP文件: $ZIP_FILE"
echo -e "5. 选择兼容的运行时: Python 3.10"
echo -e "6. 创建完成后，复制Layer ARN并更新terraform.tfvars文件"

# 复制ZIP文件到当前目录
cp "$ZIP_FILE" ./layer.zip
echo -e "${GREEN}已复制ZIP文件到当前目录: $(pwd)/layer.zip${NC}" 