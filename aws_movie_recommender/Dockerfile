# Dockerfile for the movie recommender system

# 使用一个包含Python 3.7和Flask的官方基础镜像
# 这为我们的应用提供了一个标准的运行环境
FROM python:3.7-slim-buster

# 安装一些系统级的依赖包
# - nginx: 一个高性能的Web服务器，我们将用它作为反向代理
# - ca-certificates: 用于验证SSL/TLS连接
# - libgomp1: GNU OpenMP库，某些Python科学计算库可能需要它
RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx \
    ca-certificates \
    libgomp1

# 安装Python依赖库
# - pandas, scikit-learn, scikit-surprise: 核心的机器学习和数据处理库
# - flask, gunicorn: 用于构建和运行Web应用服务器
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 设置环境变量，这些是SageMaker容器环境的标准配置
# PYTHONUNBUFFERED: 确保Python的输出（如print语句）能直接发送到终端，方便在CloudWatch中查看日志
ENV PYTHONUNBUFFERED=TRUE
# PYTHONDONTWRITEBYTECODE: 防止Python生成.pyc文件
ENV PYTHONDONTWRITEBYTECODE=TRUE
# PATH: 将训练和服务的脚本路径添加到系统PATH中，这样SageMaker可以直接调用它们
ENV PATH="/opt/program:${PATH}"

# 将本地代码复制到Docker镜像的/opt/program目录下
# 这是我们存放所有自定义脚本和代码的地方
COPY src /opt/program

# 将Nginx的配置文件复制到镜像中
# 我们用自定义的配置来覆盖默认配置
COPY nginx.conf /etc/nginx/nginx.conf

# 设置工作目录
# 后续的CMD或ENTRYPOINT指令将在这个目录下执行
WORKDIR /opt/program
