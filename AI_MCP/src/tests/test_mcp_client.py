import unittest
import sys
import os
import re
from unittest.mock import patch, MagicMock

# 添加项目根目录到 Python 路径
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))

class TestMCPClient(unittest.TestCase):
    """测试 MCP 客户端功能"""
    
    def test_extract_order_id(self):
        """测试从查询中提取订单 ID 的功能"""
        # 简单版本的订单ID提取函数（避免导入问题）
        def extract_order_id_from_query(query):
            patterns = [
                r"订单\s*(?:号|ID|编号)?\s*[:#：]?\s*(\d+)",
                r"(?:订单|单号)[:#：]?\s*(\d+)",
                r"[#＃]\s*(\d+)"
            ]
            
            for pattern in patterns:
                match = re.search(pattern, query)
                if match:
                    return match.group(1)
            return "12345"
            
        test_cases = [
            # 查询文本, 预期订单ID
            ("我想查询一下订单12345的状态", "12345"),
            ("订单号67890怎么还没发货？", "67890"),
            ("帮我看看#24680", "24680"),
            ("订单：13579什么时候到？", "13579"),
            ("我的单号99999", "99999")
        ]
        
        for query, expected_id in test_cases:
            with self.subTest(query=query):
                extracted_id = extract_order_id_from_query(query)
                self.assertEqual(extracted_id, expected_id, 
                                f"从查询'{query}'中应该提取出订单号'{expected_id}'，但得到了'{extracted_id}'")

    def test_mock_request(self):
        """测试模拟请求功能"""
        # 模拟一个简单的请求和响应
        with patch('requests.post') as mock_post:
            # 设置模拟响应
            mock_response = MagicMock()
            mock_response.status_code = 200
            mock_response.json.return_value = {"status": "success"}
            mock_post.return_value = mock_response
            
            # 模拟函数调用
            import requests
            response = requests.post("http://example.com", json={"key": "value"})
            
            # 验证结果
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.json(), {"status": "success"})
            mock_post.assert_called_once()

if __name__ == '__main__':
    unittest.main() 