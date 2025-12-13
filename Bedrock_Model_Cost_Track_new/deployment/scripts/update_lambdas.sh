#!/bin/bash

# Lambda函数更新脚本
# 用于快速更新修改后的Lambda函数

set -e

REGION="us-east-1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/../../src/lambda"

echo "🚀 开始更新Lambda函数..."

# 创建临时目录
TEMP_DIR=$(mktemp -d)
echo "📁 临时目录: $TEMP_DIR"

# 函数1: 成本管理Lambda
echo "📦 打包成本管理Lambda函数..."
cd "$TEMP_DIR"
mkdir cost_management
cp "$SRC_DIR/lambda_function_cost_management.py" cost_management/lambda_function.py
cp "$SRC_DIR/requirements.txt" cost_management/
cp "$SRC_DIR/redis_cache.py" cost_management/ 2>/dev/null || echo "⚠️  Redis缓存文件不存在，跳过"
cp "$SRC_DIR/idempotency_protection.py" cost_management/ 2>/dev/null || echo "⚠️  幂等性保护文件不存在，跳过"

# 如果存在Redis依赖，复制Redis库
if [ -d "$SRC_DIR/redis" ]; then
    cp -r "$SRC_DIR/redis" cost_management/
    cp -r "$SRC_DIR/redis-7.1.0.dist-info" cost_management/
    echo "✅ 已包含Redis依赖"
fi

cd cost_management
zip -r ../cost_management.zip . > /dev/null
echo "✅ 成本管理Lambda包已创建"

# 函数2: 资源组Lambda  
echo "📦 打包资源组Lambda函数..."
cd "$TEMP_DIR"
mkdir resource_groups
cp "$SRC_DIR/lambda_function_resource_groups.py" resource_groups/lambda_function.py
cp "$SRC_DIR/requirements.txt" resource_groups/
cp "$SRC_DIR/redis_cache.py" resource_groups/ 2>/dev/null || echo "⚠️  Redis缓存文件不存在，跳过"

# 如果存在Redis依赖，复制Redis库
if [ -d "$SRC_DIR/redis" ]; then
    cp -r "$SRC_DIR/redis" resource_groups/
    cp -r "$SRC_DIR/redis-7.1.0.dist-info" resource_groups/
    echo "✅ 已包含Redis依赖"
fi

cd resource_groups
zip -r ../resource_groups.zip . > /dev/null
echo "✅ 资源组Lambda包已创建"

# 更新Lambda函数
echo "🔄 更新Lambda函数..."

# 获取现有函数名
COST_FUNCTION=$(aws lambda list-functions --region $REGION --query "Functions[?contains(FunctionName, 'cost') || contains(FunctionName, 'Cost')].FunctionName" --output text | tr '\t' '\n' | head -1)
RESOURCE_FUNCTION=$(aws lambda list-functions --region $REGION --query "Functions[?contains(FunctionName, 'resource') || contains(FunctionName, 'Resource')].FunctionName" --output text | tr '\t' '\n' | head -1)

if [ -n "$COST_FUNCTION" ]; then
    echo "🔄 更新成本管理函数: $COST_FUNCTION"
    aws lambda update-function-code \
        --region $REGION \
        --function-name "$COST_FUNCTION" \
        --zip-file fileb://"$TEMP_DIR/cost_management.zip" > /dev/null
    echo "✅ 成本管理函数更新完成"
else
    echo "❌ 未找到成本管理Lambda函数"
fi

if [ -n "$RESOURCE_FUNCTION" ]; then
    echo "🔄 更新资源组函数: $RESOURCE_FUNCTION"
    aws lambda update-function-code \
        --region $REGION \
        --function-name "$RESOURCE_FUNCTION" \
        --zip-file fileb://"$TEMP_DIR/resource_groups.zip" > /dev/null
    echo "✅ 资源组函数更新完成"
else
    echo "❌ 未找到资源组Lambda函数"
fi

# 清理临时文件
rm -rf "$TEMP_DIR"
echo "🧹 临时文件已清理"

echo "🎉 Lambda函数更新完成！"
echo ""
echo "📋 后续步骤："
echo "1. 运行测试验证: cd tests/e2e && python3 run_all_tests.py"
echo "2. 检查函数日志: aws logs tail /aws/lambda/FUNCTION_NAME --follow"
