# 车辆实时监控系统

这是一个基于AWS的车辆实时监控系统，用于收集、处理和分析车辆数据。

## 系统架构

系统使用以下AWS服务：
- Amazon Kinesis Data Streams：用于数据流处理
- AWS Lambda：用于数据生成和处理
- Amazon Timestream：用于时间序列数据存储
- Amazon QuickSight：用于数据可视化

### 1. 演示模拟架构（当前实现）

![车辆实时监控系统架构图](image/车辆实时监控系统架构.jpg)

架构图说明：
1. **数据源层**：车辆传感器收集各种遥测数据
2. **数据处理层**：
   - 数据生成器Lambda函数：模拟或接收车辆数据，并写入Kinesis数据流
   - CloudWatch事件触发器：定时触发数据生成
   - Kinesis数据流：作为数据管道，连接生成器和处理器
   - 数据处理器Lambda函数：消费Kinesis数据，进行处理后存入Timestream
3. **数据存储层**：Timestream时间序列数据库存储处理后的车辆数据
4. **数据可视化层**：QuickSight创建仪表板，供Web浏览器和移动应用访问

该架构实现了完整的数据流转过程，从数据采集到处理、存储和可视化，构建了一个完整的车辆监控解决方案。

> **注意：目前监控数据为模拟生成，未接入真实车辆IoT设备。**

### 2. 实际车联网车辆监控架构（IoT方案设计）

实际车联网场景下，车辆传感器数据通过IoT技术方案实时上传至云平台，架构如下：

![实际车联网车辆监控架构](image/Vehicle_IoT_Architecture.jpg)

#### 数据流说明

1. 车载传感器采集数据，发送给车载网关
2. 车载网关预处理数据，发送给IoT SDK
3. IoT SDK通过MQTT协议推送数据
4. 数据进入AWS IoT Core消息代理
5. 消息代理分发到Kinesis进行实时处理
6. 消息代理分发到Timestream进行时序存储
7. Timestream存储数据
8. 消息代理分发到S3进行原始数据存储
9. S3存储数据
10. Kinesis处理结果进入Lambda
11. Timestream数据进入Lambda
12. S3数据进入Lambda
13. Lambda进行数据分析
14. Lambda触发告警
15. Lambda生成可视化数据
16. Web应用展示实时监控
17. Web应用展示数据分析
18. Web应用展示告警管理
19. 数据分析结果推送到Web应用
20. 告警结果推送到Web应用
21. 可视化结果推送到Web应用

> **说明：本架构为实际车联网场景设计，当前项目未做实际部署，监控数据仍为模拟。**

## 项目结构

```
vehicle-monitoring/
├── lambda_data_generator/      # Lambda数据生成器
│   └── vehicle_data_generator_lambda.py
├── lambda_stream_processor/    # Lambda流处理器
│   └── vehicle_processor_lambda.py
├── data_generator/             # 本地数据生成器(旧版)
│   └── vehicle_data_generator.py
├── stream_processor/           # 本地流处理器(旧版)
│   └── vehicle_processor.py
├── infrastructure/             # 基础设施代码
│   └── terraform/
│       └── main.tf
├── image/                      # 图片资源
│   ├── Vehicle_IoT_Architecture.jpg
│   ├── terraform_init.jpg
│   ├── terraform_plan.jpg
│   ├── terraform_apply.jpg
│   ├── Kinesis_monitor.jpg
│   ├── TimeStream.jpg
│   └── 车辆实时监控系统架构.jpg
└── README.md
```

> **注意：** 本地数据生成器(data_generator)和本地流处理器(stream_processor)用于在开发阶段测试功能，测试时需要同时运行这两个组件。Lambda函数是生产环境使用的最终解决方案。

## 功能特点

1. 实时数据生成
   - 模拟车辆位置、速度、温度等指标
   - 支持多车辆同时监控
   - 可配置的数据生成频率

2. 实时数据处理
   - 数据清洗和转换
   - 异常检测和告警
   - 实时指标计算

3. 数据存储和分析
   - 时间序列数据存储
   - 历史数据查询
   - 实时数据可视化

## 部署步骤

1. 安装依赖
```bash
pip install -r requirements.txt
```

2. 配置AWS凭证
```bash
aws configure
```

3. 打包Lambda函数
```bash
# 打包数据生成器
cd lambda_data_generator
zip -r vehicle_data_generator_lambda.zip vehicle_data_generator_lambda.py
# 打包流处理器
cd ../lambda_stream_processor
zip -r vehicle_processor_lambda.zip vehicle_processor_lambda.py
```

4. 部署基础设施
```bash
cd ../infrastructure/terraform
terraform init
terraform plan
terraform apply
```

![Terraform初始化](image/terraform_init.jpg)

执行terraform plan查看将要创建的资源：

![Terraform计划](image/terraform_plan.jpg)

执行terraform apply部署所有资源：

![Terraform应用](image/terraform_apply.jpg)

5. 数据生成和处理
   现在数据生成和处理都已经迁移到AWS Lambda函数，无需手动启动本地脚本。部署完成后：
   - 数据生成器Lambda函数会被CloudWatch Events每分钟触发一次
   - 数据处理器Lambda函数会自动响应Kinesis数据流中的新数据
   - 所有处理后的数据会被存储到Timestream数据库中

   您可以通过AWS控制台监控这些服务的运行状态：
   - 查看CloudWatch日志了解Lambda函数的执行情况
   - 查看Kinesis数据流监控面板了解数据流量
   - 查看Timestream查询界面查询和分析存储的数据

## 监控指标

系统收集以下车辆指标：
- 位置（经纬度）
- 速度
- 发动机温度
- 油量
- 电池电压
- 轮胎压力

## 告警规则

系统配置了以下告警规则：
- 速度超过100km/h
- 发动机温度超过110°C
- 油量低于20%
- 电池电压低于12V

## 数据可视化

使用Amazon QuickSight创建以下仪表板：
1. 实时车辆位置地图
2. 车辆状态概览
3. 告警统计
4. 历史趋势分析

### AWS控制台监控

除了QuickSight仪表板外，您还可以通过AWS控制台直接监控系统运行状态：

#### Kinesis数据流监控

通过Kinesis控制台可以监控数据流的吞吐量、分片使用情况等指标：

![Kinesis监控](image/Kinesis_monitor.jpg)

#### Timestream数据查询

通过Timestream控制台可以执行SQL查询，分析存储的车辆数据：

![Timestream查询](image/TimeStream.jpg)

## 注意事项

1. 确保AWS账户有足够的权限
2. 监控Lambda函数的执行时间和内存使用
3. 定期检查Timestream的数据保留策略
4. 根据实际需求调整数据生成频率和Lambda函数触发频率
5. 注意查看CloudWatch日志以排查潜在问题
6. **本地开发测试**：如果需要在本地测试功能，可以使用data_generator和stream_processor目录下的脚本：
   ```bash
   # 终端1：启动流处理器（消费者）
   cd stream_processor
   python vehicle_processor.py
   
   # 终端2：启动数据生成器（生产者）
   cd data_generator
   python vehicle_data_generator.py
   ```
   注意：必须先启动流处理器（消费者），再启动数据生成器（生产者），或者两者同时运行，消费者才能接收到数据。

## 扩展建议

1. 添加机器学习模型进行异常检测
2. 集成SNS进行告警通知
3. 添加车辆维护预测功能
4. 实现车队管理功能 