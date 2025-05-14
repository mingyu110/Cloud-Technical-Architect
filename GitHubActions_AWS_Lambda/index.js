/**
 * 示例 AWS Lambda 函数
 * 用于测试 GitHub Actions 部署流水线
 */

exports.handler = async (event, context) => {
    console.log('收到事件:', JSON.stringify(event, null, 2));
    
    try {
        // 处理请求
        const response = {
            statusCode: 200,
            body: JSON.stringify({
                message: 'Hello from Lambda!',
                version: '1.0.0',
                timestamp: new Date().toISOString(),
                requestId: context.awsRequestId,
                deployedBy: process.env.DEPLOYED_BY || 'Unknown',
                commitSha: process.env.COMMIT_SHA || 'Unknown'
            })
        };
        
        console.log('响应:', JSON.stringify(response, null, 2));
        return response;
    } catch (error) {
        console.error('错误:', error);
        return {
            statusCode: 500,
            body: JSON.stringify({
                message: 'Internal Server Error',
                error: error.message
            })
        };
    }
}; 