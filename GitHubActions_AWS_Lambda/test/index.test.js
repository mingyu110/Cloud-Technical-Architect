/**
 * Lambda 函数测试
 */
const { handler } = require('../index');

// 模拟 AWS Lambda 上下文
const mockContext = {
  awsRequestId: 'test-request-123',
  functionName: 'test-lambda-function',
  functionVersion: '$LATEST',
  getRemainingTimeInMillis: () => 1000
};

// 模拟事件
const mockEvent = {
  httpMethod: 'GET',
  path: '/test',
  headers: {
    'Content-Type': 'application/json'
  },
  queryStringParameters: {
    name: 'Test User'
  }
};

describe('Lambda 函数测试', () => {
  test('应返回 200 状态码和正确的响应格式', async () => {
    // 设置环境变量
    process.env.DEPLOYED_BY = 'Test Runner';
    process.env.COMMIT_SHA = 'abc1234';
    
    // 调用函数
    const response = await handler(mockEvent, mockContext);
    
    // 验证响应
    expect(response.statusCode).toBe(200);
    
    // 解析响应体
    const body = JSON.parse(response.body);
    
    // 验证响应字段
    expect(body).toHaveProperty('message');
    expect(body).toHaveProperty('version');
    expect(body).toHaveProperty('timestamp');
    expect(body).toHaveProperty('requestId', mockContext.awsRequestId);
    expect(body).toHaveProperty('deployedBy', 'Test Runner');
    expect(body).toHaveProperty('commitSha', 'abc1234');
  });
  
  test('应处理错误并返回 500 状态码', async () => {
    // 模拟错误情况
    const mockErrorEvent = { ...mockEvent, triggerError: true };
    
    // 修改函数临时抛出错误
    const originalHandler = handler;
    const mockHandler = async (event, context) => {
      if (event.triggerError) {
        throw new Error('测试错误');
      }
      return originalHandler(event, context);
    };
    
    // 替换导出的处理程序
    module.exports.handler = mockHandler;
    
    try {
      // 调用函数
      const response = await mockHandler(mockErrorEvent, mockContext);
      
      // 验证响应
      expect(response.statusCode).toBe(500);
      
      // 解析响应体
      const body = JSON.parse(response.body);
      
      // 验证错误信息
      expect(body).toHaveProperty('message', 'Internal Server Error');
      expect(body).toHaveProperty('error', '测试错误');
    } finally {
      // 恢复原始处理程序
      module.exports.handler = originalHandler;
    }
  });
}); 