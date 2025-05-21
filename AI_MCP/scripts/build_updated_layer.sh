#!/bin/bash
set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# Python镜像地址 - 使用AWS Lambda Python 3.11镜像
PYTHON_IMAGE="public.ecr.aws/lambda/python:3.11"

# 检查当前目录是否可写
if [ ! -w . ]; then
    echo -e "${RED}错误：当前目录不可写，请确保有写入权限${NC}"
    exit 1
fi

# 检查是否安装了Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}错误：未安装Docker，请先安装Docker${NC}"
    exit 1
fi

# 创建临时目录
TEMP_DIR=$(mktemp -d)
CURRENT_DIR=$(pwd)

# 清理函数
cleanup() {
    echo -e "${BLUE}清理临时目录...${NC}"
    rm -rf "$TEMP_DIR"
}

# 设置退出时清理
trap cleanup EXIT

echo -e "${BLUE}===== 开始准备更新的Lambda Layer依赖（容器化构建）=====${NC}"
echo -e "${BLUE}临时目录: $TEMP_DIR${NC}"
echo -e "${BLUE}使用镜像: $PYTHON_IMAGE${NC}"

# 创建requirements.txt文件 - 包含新的MCP依赖
cat > "$TEMP_DIR/requirements.txt" << EOF
boto3>=1.28.0
requests>=2.31.0
mcp>=1.9.0
run-mcp-servers-with-aws-lambda>=0.1.5
pytest>=7.4.0
pydantic>=2.0.0
mangum>=0.17.0
EOF

# 创建pip配置文件
mkdir -p "$TEMP_DIR/.pip"
cat > "$TEMP_DIR/.pip/pip.conf" << EOF
[global]
timeout = 120
index-url = https://mirrors.aliyun.com/pypi/simple/
trusted-host = mirrors.aliyun.com
EOF

echo -e "${BLUE}创建的requirements.txt文件内容:${NC}"
cat "$TEMP_DIR/requirements.txt"

echo -e "${BLUE}使用的pip配置:${NC}"
cat "$TEMP_DIR/.pip/pip.conf"

# 使用Docker安装依赖
echo -e "${BLUE}使用Docker安装依赖...${NC}"
echo -e "${BLUE}这将安装MCP 1.9.0+ 和 run-mcp-servers-with-aws-lambda 0.1.5+...${NC}"
echo -e "${BLUE}注意: 由于依赖要求，使用Python 3.11构建...${NC}"

# AWS Lambda镜像已经包含Python和pip
docker run --rm --entrypoint /bin/bash -v "$TEMP_DIR:/var/task" $PYTHON_IMAGE -c "
    mkdir -p /var/task/python && 
    mkdir -p /root/.pip && 
    cp /var/task/.pip/pip.conf /root/.pip/ && 
    pip --version && 
    python --version &&
    pip install --no-cache-dir -r /var/task/requirements.txt -t /var/task/python && 
    echo '列出已安装的包:' &&
    ls -la /var/task/python/ &&
    pip list &&
    # 安装zip工具
    yum install -y zip && 
    cd /var/task && 
    zip -r layer.zip python
"

if [ $? -ne 0 ]; then
    echo -e "${RED}错误：Docker中依赖安装或打包失败${NC}"
    exit 1
fi

echo -e "${BLUE}检查ZIP文件内容:${NC}"
if ! unzip -l "$TEMP_DIR/layer.zip" | grep -i "mcp"; then
    echo -e "${YELLOW}警告：未在ZIP文件中找到mcp包${NC}"
fi

if ! unzip -l "$TEMP_DIR/layer.zip" | grep -i "run-mcp-servers-with-aws-lambda"; then
    echo -e "${YELLOW}警告：未在ZIP文件中找到run-mcp-servers-with-aws-lambda包${NC}"
fi

# 复制ZIP文件到当前目录
if ! cp "$TEMP_DIR/layer.zip" ./updated_layer_py311.zip; then
    echo -e "${RED}错误：无法复制ZIP文件到当前目录${NC}"
    exit 1
fi

echo -e "${GREEN}===== 更新的Layer依赖已准备完成 =====${NC}"
echo -e "${GREEN}ZIP文件位置: $(pwd)/updated_layer_py311.zip${NC}"
echo -e "${YELLOW}现在您可以登录AWS控制台，创建Lambda Layer:${NC}"
echo -e "1. 登录AWS管理控制台，进入Lambda服务"
echo -e "2. 在左侧导航栏选择\"Layers\""
echo -e "3. 点击\"Create layer\"按钮"
echo -e "4. 填写Layer信息（建议名称: mcp-layer-py311-v1），上传ZIP文件: $(pwd)/updated_layer_py311.zip"
echo -e "5. 选择兼容的运行时: Python 3.11"
echo -e "6. 选择兼容的架构: x86_64"
echo -e "7. 创建完成后，复制Layer ARN"

echo -e "${YELLOW}重要: 您需要同时更新Lambda函数的运行时为Python 3.11${NC}"
echo -e "1. 更新terraform配置中的runtime设置为\"python3.11\""
echo -e "2. 更新terraform.tfvars文件中的lambda_layer_arn变量"

echo -e "${GREEN}构建完成！${NC}" 