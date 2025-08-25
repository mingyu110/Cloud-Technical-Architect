# 使用 AWS Lake Formation 构建数据湖实践

#### 数据湖的必要性与核心挑战

数据湖架构旨在通过统一的中央存储库，解决传统数据系统在处理海量、多格式数据时面临的灵活性、成本和可扩展性问题，以支持从商业智能（BI）到高级分析（如机器学习）等多样化的分析负载，从而打破数据孤岛，提升业务敏捷性。

然而，构建功能完善的数据湖面临四大核心挑战：

1.  **数据治理与安全合规**：需建立覆盖数据质量、血缘、生命周期和隐私合规（如GDPR）的全面治理体系。
2.  **统一元数据管理**：需通过集中的数据目录管理技术与业务元数据，确保数据可被发现、理解并保持语义一致性。
3.  **精细化访问控制**：需在存储层的粗粒度权限之上，跨多计算引擎实现统一的、精确到库、表、列级的细粒度访问授权。
4.  **数据集成与架构演进**：需构建能高效摄取多源异构数据，并能平滑适应源端数据结构变更的健壮数据管道。

![构建数据湖的挑战](https://www.pythian.com/hubfs/Imported_Blog_Media/image-45.png)

#### AWS Lake Formation 简介

Lake Formation 是 AWS 提供的一项完全托管的服务，使数据工程师、安全官和数据分析师能够构建、保护、管理和使用数据湖。

创建数据湖有三个阶段：

阶段一：注册数据湖存储位置。

阶段二：在数据湖的数据目录中创建数据库。

阶段三：授予对数据湖资源和底层数据的权限。

![Lake Formation 阶段](https://www.pythian.com/hubfs/Imported_Blog_Media/image-43-1.png)

在本文中，将基于 AWSLake Formation 为 [COVID-19 数据](https://pandemicdatalake.blob.core.windows.net/public/curated/covid-19/bing_covid-19_data/latest/bing_covid-19_data.parquet) 构建一个演示数据湖，并逐步介绍构建、保护、管理和使用该数据湖的所有步骤。本文将设置以下资源：

1.  在 S3 上设置带有示例文件的数据位置。
2.  设置 AWS Lake Formation 并创建一个数据库。
3.  设置 Glue 爬网程序以收集表元数据。
4.  使用 Athena 查询数据。

**注：**本文的实践为了功能展示更加直观，使用了AWS控制台进行资源创建和配置的方式。

#### 1. 在 S3 存储桶中设置原始数据位置

创建一个示例存储桶来存储 COVID-19 的原始数据。Bing COVID-19 数据包括来自所有地区的每日更新的确诊、死亡和康复病例。这些数据反映在 [Bing COVID-19 跟踪器](https://bing.com/covid)中。

数据集可以[在此处](https://pandemicdatalake.blob.core.windows.net/public/curated/covid-19/bing_covid-19_data/latest/bing_covid-19_data.parquet)下载。以下是列及其示例值的列表：

| 名称             | 数据类型 | 唯一值    | 示例值 (sample)                    | 描述                                                  |
| ---------------- | --------- | --------- | ---------------------------------- | ------------------------------------------------------------ |
| admin_region_1   | string    | 864       | Texas Georgia                      | country_region 内的区域                                 |
| admin_region_2   | string    | 3,143     | Washington County Jefferson County | admin_region_1 内的区域                                 |
| confirmed        | int       | 120,692   | 1 2                                | 该区域的确诊病例数                          |
| confirmed_change | int       | 12,120    | 1 2                                | 与前一天相比的确诊病例数变化         |
| country_region   | string    | 237       | United States India                | 国家/地区                                               |
| deaths           | int       | 20,616    | 1 2                                | 该区域的死亡病例数                              |
| deaths_change    | smallint  | 1,981     | 1 2                                | 与前一天相比的死亡人数变化                  |
| id               | int       | 1,783,534 | 742546 69019298                    | 唯一标识符                                            |
| iso_subdivision  | string    | 484       | US-TX US-GA                        | 两部分的 ISO 细分代码                                |
| iso2             | string    | 226       | US IN                              | 2个字母的国家代码标识符                             |
| iso3             | string    | 226       | USA IND                            | 3个字母的国家代码标识符                             |
| latitude         | double    | 5,675     | 42.28708 19.59852                  | 区域质心的纬度                       |
| load_time        | timestamp | 1         | 2021-04-26 00:06:34.719000         | 文件从 GitHub 上的 Bing 源加载的日期和时间 |
| longitude        | double    | 5,693     | -2.5396 -155.5186                  | 区域质心的经度                      |
| recovered        | int       | 73,287    | 1 2                                | 该区域的康复病例数                               |
| recovered_change | int       | 10,441    | 1 2                                | 与前一天相比的康复病例数变化         |
| updated          | date      | 457       | 2021-04-23 2021-04-22              | 记录的截止日期                                |

来源 – https://docs.microsoft.com/en-us/azure/open-datasets/dataset-bing-covid-19?tabs=azure-storage

使用 AWSCLI 将文件复制到 S3：

```bash
# 使用 AWS CLI 命令将下载的 Parquet 文件复制到 S3 存储桶中
# 'bing_covid-19_data.parquet' 是源文件
# 's3://[BUCKET_NAME]/source' 是目标 S3 路径，请将 [BUCKET_NAME] 替换为您的存储桶名称
aws s3 cp bing_covid-19_data.parquet s3://[BUCKET_NAME]/source
```

#### 2. 设置 AWS Lake Formation

要设置数据湖，我执行以下操作：

1.  定义一个或多个管理员，他们将拥有对 Lake Formation 的完全访问权限，并负责控制初始数据配置和访问权限。
2.  注册 S3 路径。
3.  创建一个数据库。
4.  为用户提供访问数据湖的必要权限。

![设置 Lake Formation](https://www.pythian.com/hubfs/Imported_Blog_Media/image-12-1.png)

#### 2.1 定义数据湖形成系统的管理员

1.  导航到 AWS Lake Formation，在 **Permissions** 部分下选择 **Administrative roles and tasks**：

![管理角色和任务](https://www.pythian.com/hubfs/Imported_Blog_Media/image-13-1.png)

2.  在 **Data lake administrators** 部分，添加当前登录的用户，并选择要提升为 Lake Formation 管理员的其他 IAM 用户或角色：

![数据湖管理员](https://www.pythian.com/hubfs/Imported_Blog_Media/image-14-1.png)

如下所示：

![添加管理员](https://www.pythian.com/hubfs/Imported_Blog_Media/image-16-1.png)

3.  在 **Data Creators** 部分，确保 **IAMAllowedPrincipals Group** 被授予 **Create database** 权限：

![数据库创建者](https://www.pythian.com/hubfs/Imported_Blog_Media/image-17-1.png)

成功为 Lake Formation 系统设置了管理员以后继续注册 S3 位置。

#### 2.2 注册 S3 位置

注册存储我们原始数据集的 S3 位置。

1.  在 Lake Formation 控制台中，从 **Register and ingest** 部分导航到 **Data Lake Locations**：

![数据湖位置](https://www.pythian.com/hubfs/Imported_Blog_Media/image-18-1.png)

2.  选择 **Register location** 以将 S3 存储位置作为数据湖的一部分：

![注册位置](https://www.pythian.com/hubfs/Imported_Blog_Media/image-19-1.png)

3.  在 Lake Formation 中注册数据集源位置，并使用服务相关角色。必须具有创建/修改 IAM 角色的权限才能使用服务相关角色：

![注册数据集源](https://www.pythian.com/hubfs/Imported_Blog_Media/image-21-1.png)

4.  导航到 IAM 控制台，搜索 IAM 角色并查看其附加的策略：

![查看 IAM 角色](https://www.pythian.com/hubfs/Imported_Blog_Media/image-22-1.png)

5.  在 Lake Formation 中注册位置时，它会自动创建以下内联策略并将其附加到服务相关角色，此内联策略由 Lake Formation 管理：

```json
{
    "Version": "2012-10-17", // 指定策略语言的版本
    "Statement": [ // 包含一个或多个语句的列表
        {
            "Sid": "LakeFormationDataAccessPermissionsForS3", // 语句的标识符
            "Effect": "Allow", // 声明效果为“允许”
            "Action": [ // 允许对S3对象进行的操作
                "s3:PutObject", // 允许上传对象
                "s3:GetObject", // 允许下载对象
                "s3:DeleteObject" // 允许删除对象
            ],
            "Resource": [ // 指定策略应用于S3存储桶内的特定路径下的所有对象
                "arn:aws:s3:::sa-proj-datalake/source/*"
            ]
        },
        {
            "Sid": "LakeFormationDataAccessPermissionsForS3ListBucket", // 第二个语句的标识符
            "Effect": "Allow", // 声明效果为“允许”
            "Action": [ // 允许对S3存储桶本身进行的操作
                "s3:ListBucket"
            ],
            "Resource": [ // 指定策略应用于S3存储桶本身
                "arn:aws:s3:::sa-proj-datalake"
            ]
        }
    ]
}
```

6.  确保位置已成功注册，如下所示：

![位置注册成功](https://www.pythian.com/hubfs/Imported_Blog_Media/image-23-1.png)

#### 2.3 授予对数据位置的访问权限并验证权限

1.  导航到 **Data location > Permissions** 部分：

![数据位置权限](https://www.pythian.com/hubfs/Imported_Blog_Media/image-24-1.png)

2.  Lake Formation 允许用户管理用户、角色、外部账户等的访问权限。可以向当前用户授予对数据位置的权限：

![授予权限](https://www.pythian.com/hubfs/Imported_Blog_Media/image-26.png)

3.  将当前登录的用户的权限授予数据位置，如下所示：

![授予当前用户权限](https://www.pythian.com/hubfs/Imported_Blog_Media/image-25.png)

4.  验证数据库和表的权限。导航到 **Data Catalog > Settings** 并检查是否为数据库和表启用了 IAM 访问控制：

![验证权限设置](https://www.pythian.com/hubfs/Imported_Blog_Media/image-27.png)

#### 2.4 创建数据库

1.  为了生成元数据并将其存储在数据目录中，需要创建一个数据库。要使用 Lake Formation 控制台创建数据库，必须以数据湖管理员或数据库创建者身份登录。导航到 **Data catalog > Databases**，然后创建数据库：

![创建数据库](https://www.pythian.com/hubfs/Imported_Blog_Media/image-28.png)

2.  提供源 S3 位置和数据库名称，如下所示，然后创建数据库：

![提供数据库信息](https://www.pythian.com/hubfs/Imported_Blog_Media/image-29.png)

#### 3. 使用 AWS Glue 设置爬网程序以确定表的架构：

在 AWS Glue 中设置一个爬网程序以连接到数据存储，确定架构并在数据目录中创建元数据表。

![设置爬网程序](https://www.pythian.com/hubfs/Imported_Blog_Media/image-44.png)

1.  导航到 AWS Glue，从导航窗格的 **Data Catalog** 部分选择 **Tables**：

![Glue 表](https://www.pythian.com/hubfs/Imported_Blog_Media/image-30.png)

2.  使用爬网程序添加表，这将在数据目录中创建元数据表：

![使用爬网程序添加表](https://www.pythian.com/hubfs/Imported_Blog_Media/image-31.png)

3.  提供爬网程序名称：

![爬网程序名称](https://www.pythian.com/hubfs/Imported_Blog_Media/image-34-1.png)

4.  将源类型指定为数据存储：

![源类型](https://www.pythian.com/hubfs/Imported_Blog_Media/image-35-1.png)

5.  指定要爬网的数据源路径：

![数据源路径](https://www.pythian.com/hubfs/Imported_Blog_Media/image-36-1.png)

6.  创建一个具有必要权限以爬网数据源的新服务相关角色：

![创建服务相关角色](https://www.pythian.com/hubfs/Imported_Blog_Media/image-37-1.png)

7.  定义爬网程序的运行频率：

![运行频率](https://www.pythian.com/hubfs/Imported_Blog_Media/image-38-1.png)

8.  为爬网程序输出选择数据库。这是之前在 Lake Formation 中创建的同一个数据库：

![选择数据库](https://www.pythian.com/hubfs/Imported_Blog_Media/image-39-1.png)

9.  审查并创建爬网程序。
10. 运行爬网程序：

![运行爬网程序](https://www.pythian.com/hubfs/Imported_Blog_Media/image-41.png)

11. 等待 **Tables added** 列（如下所示）变为 1，这标志着爬网程序任务的完成以及表架构在目录中的更新。爬网程序在目录中更新或添加的任何表都由控制台中的这些列表示：

![表已添加](https://www.pythian.com/hs-fs/hubfs/Imported_Blog_Media/image-54.png?width=770&height=132&name=image-54.png)

12. 导航回 Lake Formation 和 **Data Catalog > Tables**。表应该已被爬网程序添加，其架构也必须已填充：

![查看表](https://www.pythian.com/hubfs/Imported_Blog_Media/image-42.png)

**注意**：表的名称由目录表命名算法选择，用户以后无法在控制台中更改它。如果用户需要在控制台中管理表的名称，可以手动添加表。为此，在定义爬网程序时，不要将一个或多个数据存储指定为爬网的源，而是指定一个或多个现有的数据目录表。然后，爬网程序会爬网由目录表指定的数据存储。在这种情况下，不会创建新表；而是会更新用户手动创建的表。

#### 4. 使用 Athena 查询数据

![使用 Athena 查询数据](https://www.pythian.com/hubfs/Imported_Blog_Media/image-51.png)

1.  导航到 AWS Athena，转到设置并更新 S3 的查询结果位置路径，如下所示：

![Athena 设置](https://www.pythian.com/hubfs/Imported_Blog_Media/image-46.png)

2.  选择数据库并运行查询以查看表的结果：

![运行查询](https://www.pythian.com/hubfs/Imported_Blog_Media/image-47.png)

#### 管理数据权限

##### 为何需要 Lake Formation 进行权限管理？

传统的云上数据权限管理主要依赖于 IAM 和 S3 存储桶策略。这种方式存在明显局限性，因为它是一种**与基础设施强绑定**的粗粒度控制模型：
- **缺乏数据感知**：IAM 只能理解“S3 路径” (例如 `s3://my-bucket/my-folder/*`)，而无法理解“数据库”、“表”或“列”这些业务和数据分析人员关心的逻辑概念。因此，无法实现“允许用户A访问客户表的姓名和邮箱列，但禁止访问地址列”这类精细化的业务需求。
- **策略分散且复杂**：权限策略分散在不同的 IAM 用户/角色和 S3 存储桶上，难以集中审计和管理。当计算引擎多样化（如同时使用 Athena、EMR、Redshift Spectrum）时，需要在多个地方维护相似的权限，极易出错。

AWS Lake Formation 从根本上解决了这些问题。它提供了一个**集中式的、与数据目录绑定的逻辑权限模型**。管理员可以完全从业务视角出发，使用熟悉的 `GRANT/REVOKE` 语法，对用户授予或撤销特定数据库、表、乃至列的访问权限。这些权限策略被集中存储和管理，并由 Lake Formation 自动在所有集成的计算引擎上强制执行。这**极大地简化了数据湖的安全治理，使其能更好地满足企业复杂和动态的业务需求**。

##### 权限授予实践

**数据库级别权限**：可以使用控制台在 Lake Formation 中授予或撤销对 IAM 用户或角色的数据库权限：

![数据库权限](https://www.pythian.com/hubfs/Imported_Blog_Media/image-48.png)

可以添加新用户、角色、外部用户或活动目录用户，并可以授予对数据库所需级别的访问权限。请参阅下图以供参考：

![授予数据库权限](https://www.pythian.com/hubfs/Imported_Blog_Media/image-52.png)

**表级别权限**：您可以使用控制台授予或撤销对 IAM 用户的表权限。表级别权限可以是精细级别的，您可以定义对表的 select\insert\delete 访问权限。请参阅下图以供参考：

![表权限](https://www.pythian.com/hubfs/Imported_Blog_Media/image-53.png)

#### 总结

我们已经成功使用 Lake Formation 设置了数据湖、数据库和数据目录。Lake Formation 还允许我们在数据库和表级别管理对数据湖资源的访问，这有助于管理数据湖资源的权限。总的来说，Lake Formation 简化了在 AWS 中设置数据湖的过程。

#### 参考文档

1. [**AWS Lake Formation: How it works**](https://docs.aws.amazon.com/lake-formation/latest/dg/how-it-works.html) 

2. [**Using crawlers to populate the Data Catalog**]( https://docs.aws.amazon.com/glue/latest/dg/add-crawler.html) 

3. [**AWS Glue Data Catalog**]( https://docs.aws.amazon.com/prescriptive-guidance/latest/serverless-etl-aws-glue/aws-glue-data-catalog.html) 
