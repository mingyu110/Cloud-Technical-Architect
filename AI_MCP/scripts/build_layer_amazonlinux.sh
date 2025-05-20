#!/bin/bash
set -e

echo "=== 使用Amazon Linux 2环境构建Lambda Layer ==="
echo "注意: 此脚本需要Docker"

# 检查Docker是否可用
if ! command -v docker &> /dev/null; then
    echo "错误: Docker未安装或未运行。请安装Docker并确保它正在运行。"
    exit 1
fi

# 创建临时目录
TEMP_DIR=$(mktemp -d)
echo "创建临时目录: $TEMP_DIR"

# 清理函数
cleanup() {
    echo "清理临时文件..."
    rm -rf "$TEMP_DIR"
}

# 注册退出时的清理
trap cleanup EXIT

# 创建requirements.txt
cat > "$TEMP_DIR/requirements.txt" << EOF
boto3>=1.28.0
requests>=2.31.0
mcpengine[lambda]>=0.3.0
pytest>=7.4.0
pydantic>=2.0.0
mangum>=0.17.0
EOF

echo "构建Layer..."

# 使用Amazon Linux 2环境构建Layer
docker run --rm -v "$TEMP_DIR:/var/task" amazonlinux:2 /bin/bash -c "
    # 安装Python 3.10和开发工具
    amazon-linux-extras install python3.10
    yum install -y python3.10-pip python3.10-devel gcc zip
    
    # 创建python目录并安装依赖
    mkdir -p /var/task/python
    python3.10 -m pip install --upgrade pip
    python3.10 -m pip install -r /var/task/requirements.txt -t /var/task/python
    
    # 打包Layer
    cd /var/task
    zip -r layer.zip python
"

# 复制layer.zip到当前目录
cp "$TEMP_DIR/layer.zip" ./amazonlinux_layer.zip

echo "=== Layer构建完成 ==="
echo "Layer文件: $(pwd)/amazonlinux_layer.zip"
echo ""
echo "接下来步骤:"
echo "1. 登录AWS控制台，上传这个新的Layer"
echo "2. 更新Lambda函数使用这个新的Layer" 