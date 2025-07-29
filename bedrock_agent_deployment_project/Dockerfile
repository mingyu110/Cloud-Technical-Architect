# 使用 uv 的官方 Python 基础镜像，确保环境纯净且高效
FROM ghcr.io/astral-sh/uv:python3.11-bookworm-slim

# 设置工作目录
WORKDIR /app

# 复制项目的核心文件到容器中
# 我们只复制必要的文件，以保持镜像的最小化
COPY pyproject.toml uv.lock* README.md ./
COPY src/ src/

# 使用 uv 安装锁定的依赖项
# --frozen 确保只安装 lock 文件中指定的版本
# --no-cache 减少镜像体积
RUN uv sync --frozen --no-cache

# 暴露应用运行的端口
EXPOSE 8080

# 定义容器启动命令
# 使用 uvicorn 启动 src.agent.main 中的 app 实例
CMD ["uv", "run", "uvicorn", "src.agent.main:app", "--host", "0.0.0.0", "--port", "8080"]
