### 技术实践白皮书：云上CAE/CFD工作负载的数据架构现代化

**作者前言**

在阿里云工作期间，我有幸参与了一些从事HPC业务的客户的研发流程向云端的现代化转型项目。在此过程中，我们发现，无论客户的业务背景如何，当CAE/CFD这类典型的高性能计算（HPC）工作负载上云时，他们都会面临一个共同的核心挑战：**如何平衡海量仿真数据对“高性能”和“低成本”这两种看似矛盾的存储需求？**

本文旨在分享我们当时为客户设计并成功落地的一套**“分离式数据架构”**。该架构不仅解决了上述核心挑战，更已成为当前云上HPC数据管理的最佳实践。同时，本文也将对业界两大领先的云服务商——**阿里云**与**Amazon Web Services (AWS)**——在此架构下的核心技术实现进行对等的分析与比较。

---

#### 1. 现代CAE/CFD云架构的核心模式：分离式数据架构

传统本地HPC集群的存储通常是单一、昂贵的并行文件系统，既要承担高性能计算，又要负责长期数据存储，成本高昂且缺乏弹性。云为此提供了破局的思路：将存储根据功能进行解耦，构建一个分离式的现代化数据架构。

此架构模式包含三个关键组成部分：

1.  **持久化数据湖层 (The Persistent Data Lake Layer)**
    *   **角色**：作为所有仿真数据的“单一事实来源（Single Source of Truth）”。所有原始输入文件、算例、求解器版本和最终的仿真结果都应长期、安全地存放在此。
    *   **技术选型**：**对象存储**是此层的必然选择，因其具备近乎无限的扩展性、高持久性和极低的存储成本。
        *   **阿里云**: [对象存储服务 (OSS)](https://www.alibabacloud.com/zh/product/object-storage-service)
        *   **AWS**: [Amazon Simple Storage Service (S3)](https://aws.amazon.com/s3/)

2.  **高性能计算缓存层 (The High-Performance Compute Cache Layer)**
    *   **角色**：这是一个临时的、按需创建的高性能“暂存空间”，专门服务于计算过程中的密集型I/O需求。它需要提供完全的POSIX文件系统接口和极高的读写吞吐量。
    *   **技术选型**：**托管的并行文件系统**是此层的最佳选择。
        *   **阿里云**: [云并行文件系统 (CPFS)](https://www.alibabacloud.com/zh/product/cpfs)
        *   **AWS**: [Amazon FSx for Lustre](https://aws.amazon.com/fsx/lustre/)

3.  **智能数据联动机制 (The Intelligent Data Fabric)**
    *   **角色**：这是连接上述两层的“桥梁”和“大脑”，负责按需、自动、高效地在数据湖层和高性能缓存层之间同步数据。它的智能化程度，直接决定了整个架构的效率和易用性。

---

#### 2. 解决方案实现：两大云厂商的技术对标

阿里云和AWS均为此架构提供了功能高度对等、实现逻辑一致的核心技术。

##### 2.1. 阿里云解决方案：CPFS 与 数据流动 (Data Flow)

*   **核心技术**：阿里云CPFS的**“数据流动”**功能是实现智能数据联动的关键。
*   **工作机制**：
    1.  **关联**：用户可以在一个CPFS文件系统和一个指定的OSS存储桶之间建立“数据流动”关联。
    2.  **数据导入（惰性加载）**：当关联建立后，CPFS可以仅同步OSS中的元数据。计算节点能立刻看到所有文件和目录，但文件内容只有在被首次访问时，才会按需、透明地从OSS加载到CPFS中。
    3.  **数据导出（自动归档）**：在CPFS中新创建或修改的文件，可以被“数据流动”任务自动、异步地写回到OSS中，完成结果的持久化。
*   **集群管理**：通过 **[阿里云弹性高性能计算 (EHPC)](https://www.alibabacloud.com/zh/product/ehpc)** 可以自动化地创建和管理计算集群，并自动挂载配置好数据流动功能的CPFS文件系统。

##### 2.2. AWS 解决方案：Amazon FSx for Lustre 与 数据存储库关联 (DRA)

*   **核心技术**：AWS FSx for Lustre的**“数据存储库关联（Data Repository Association, DRA）”**功能扮演了同样的角色。
*   **工作机制**：
    1.  **关联**：用户可以在一个FSx for Lustre文件系统和一个S3存储桶之间建立DRA链接。
    2.  **数据导入（惰性加载）**：DRA同样采用惰性加载机制，在文件首次被访问时才从S3拉取数据内容，极大地缩短了任务启动时间。
    3.  **数据导出（自动归档）**：DRA也可以自动将文件系统中的变更导出到S3，确保数据安全归档。
*   **集群管理**：通过 **[AWS ParallelCluster](https://aws.amazon.com/hpc/parallelcluster/)** 这一开源集群管理工具，可以同样实现计算环境和存储的自动化部署与管理。

##### 2.3. 功能对等性总结

| 架构层级 | 阿里云实现 | AWS实现 | 功能对等性 |
| :--- | :--- | :--- | :--- |
| **数据湖层** | Alibaba Cloud OSS | Amazon S3 | **高度对等** |
| **高性能缓存层** | CPFS | Amazon FSx for Lustre | **高度对等** |
| **智能数据联动** | **数据流动 (Data Flow)** | **Data Repository Association (DRA)** | **高度对等** |
| **集群管理工具** | EHPC | AWS ParallelCluster | **高度对等** |

结论是，两大云厂商均提供了成熟且功能对等的工具链，来完美地支持我们所倡导的分离式数据架构。

---

#### 3. 实践工作流：一个端到端的优化范例

基于上述架构，我们为客户成功实施的典型工作流如下：

1.  **步骤一：构建统一数据湖**
    将所有项目的输入文件、算例、求解器等长期数据，结构化地存放在对象存储（OSS 或 S3）中。

2.  **步骤二：按需启动计算环境**
    当需要进行仿真计算时，通过集群管理工具（EHPC 或 AWS ParallelCluster）在数分钟内按需启动一个计算集群。该工具会自动创建一个临时的并行文件系统（CPFS 或 FSx for Lustre），并将其与对象存储中的项目数据目录建立智能关联。

3.  **步骤三：执行计算并利用惰性加载**
    工程师提交计算作业。求解器启动后，能立即通过挂载的文件系统路径访问输入文件。由于惰性加载机制，求解器无需等待TB级的输入文件下载，计算即刻开始。计算过程中产生的结果文件直接写入此高性能文件系统。

4.  **步骤四：结果归档与资源销毁**
    计算任务完成后，智能数据联动机制会自动将新生成的结果文件同步回对象存储中进行持久化归档。一旦确认数据归档完毕，即可通过管理工具一键销毁整个计算环境，包括昂贵的计算实例和并行文件系统。

---

#### 4. 实践深化：面向多类型工作负载的弹性集群管理

在理解了端到端工作流后，一个更深入的实践问题是：如何在统一的集群环境中，高效且经济地支持前处理（通常是内存密集型）、求解（通信或计算密集型）和后处理（计算或图形密集型）等不同类型的计算任务。

答案是放弃“用一种硬件通吃所有任务”的传统思路，转而构建一个**能动态适应不同类型工作负载的、资源异构的弹性环境**。以下是实现此目标的核心策略。

##### **4.1. 构建异构计算队列 (Heterogeneous Compute Queues)**

这是最核心的策略。我们不在集群中配置单一类型的计算节点，而是在同一个集群调度器下，定义多个、专门化的计算队列（Queue/Partition），每个队列关联不同类型的云服务器实例。

*   **内存密集型队列**: 配置使用内存优化型实例（如AWS R系列/Hpc6id，阿里云re系列），专门用于大规模网格生成等任务。
*   **通信密集型队列**: 配置使用支持低延迟网络（如AWS EFA，阿里云eRDMA）的HPC实例，专门用于大规模、紧耦合的并行求解。
*   **计算密集型队列**: 配置使用计算优化型实例，其CPU主频高、浮点性能强，用于显式动力学等计算密集任务。
*   **GPU队列**: 配置使用GPU实例，用于需要图形加速或AI集成的任务。

当用户提交作业时，只需指定要使用的队列，调度器（如Slurm）便会自动在正确的硬件资源池中启动实例。

##### **4.2. 利用弹性伸缩实现按需分配**

为每个异构队列都设置`MinCount: 0`（最小节点数为0）的弹性伸缩策略。这意味着：
*   **平时成本最低**：当没有任何作业运行时，集群中没有任何计算节点在运行，计算成本为零。
*   **资源动态匹配**：当一个内存密集型作业和两个通信密集型作业同时提交时，系统会自动拉起两种不同类型的实例，并行处理，互不干扰。
*   **用完即毁**：作业完成后，其占用的节点在空闲一段时间后会被自动销毁，停止计费。

##### **4.3. 提供统一的存储与数据访问**

尽管计算资源是异构和动态的，但存储资源必须是统一和持久的，以确保工作流的无缝衔接。所有异构队列中的计算节点，都应挂载同一个共享文件系统（如FSx for Lustre或CPFS）。这使得前处理阶段在内存队列中生成的网格数据，可以被求解阶段在通信队列中直接读取，无需任何数据拷贝。

通过这些策略，云上HPC集群不再是一个固定的实体，而是一个能根据科研和工程需求，动态重塑自身形态的、高度智能化的计算资源池。

---

#### 5. 结论与展望

通过实施“持久化数据湖 + 高性能计算缓存 + 智能数据联动”的分离式数据架构，航空航天及制造企业能够在云上获得前所未有的敏捷性和成本效益。实践证明，无论是在阿里云还是AWS平台，这一架构都能帮助客户：
*   **将研发周期缩短30%以上**，因为工程师可以即时获取所需规模的计算资源。
*   **将TCO（总体拥有成本）降低50%以上**，因为昂贵的HPC资源实现了按需使用，杜绝了闲置浪费。
*   **建立起可复用、可追溯的中央数据资产**，为未来的AI/ML数据分析和数字孪生应用奠定了坚实的基础。

可以预见，这种云原生的分离式数据架构将成为未来所有数据密集型科学与工程计算领域的标准范式。

---

### **附录：基础设施即代码（IaC）实践——自动化HPC环境部署**

“在数分钟内启动集群”的核心是**基础设施即代码（Infrastructure as Code, IaC）**的理念。即通过编写可读的配置文件来定义和管理所有云资源，从而实现部署的自动化、可重复性
##### **4.4. 利用作业调度器实现工作流编排**

使用调度器的作业依赖功能，可以自动化地编排多阶段、多资源需求的复杂工作流。例如，可以设置一个规则，让通信密集型的求解作业，必须在内存密集型的网格生成作业成功完成后才能自动开始。

| 需求 | 管理策略 | 关键技术/工具 |
| :--- | :--- | :--- |
| **应对不同负载类型** | **异构计算队列** | `AWS ParallelCluster`/`阿里云EHPC` 配置文件 |
| **控制成本** | **弹性伸缩，按需分配** | `MinCount: 0` 设置，Spot实例 |
| **多阶段任务数据流转** | **统一共享存储** | `FSx for Lustre`, `EFS` / `CPFS`, `NAS` |
| **自动化工作流** | **作业依赖与编排** | 作业调度器 (Slurm, PBS) |
和版本控制。

以下是两大云平台IaC实践的简要示例。

#### **AWS 实践: AWS ParallelCluster**

AWS ParallelCluster 使用YAML文件来定义整个HPC集群的拓扑。

**`cluster-config.yaml` 示例片段:**
```yaml
# ... 其他配置 ...
SharedStorage:
  - Name: FsxLustreStorage
    StorageType: FsxLustre
    MountDir: /fsx
    FsxLustreSettings:
      # 关联到S3数据湖
      DataRepositoryPath: s3://my-cae-datalake/project-A/

Scheduling:
  Scheduler: slurm
  SlurmQueues:
    - Name: cfd-queue
      ComputeResources:
        - Name: hpc-compute-nodes
          InstanceType: hpc7g.8xlarge
          MinCount: 0  # 核心：空闲时节点数为0
          MaxCount: 128 # 核心：按需最大扩展数
# ... 其他配置 ...
```

**部署与销毁命令:**
```bash
# 创建集群 (约15-25分钟)
pcluster create-cluster --cluster-name my-cfd-cluster --cluster-configuration cluster-config.yaml

# 销毁集群 (用完即毁)
pcluster delete-cluster --cluster-name my-cfd-cluster
```

#### **阿里云实践: 弹性高性能计算 (EHPC) 与 Terraform**

阿里云EHPC同样可以通过IaC工具进行管理，Terraform是业界通用的选择。

**`main.tf` 示例片段:**
```terraform
# ... 其他配置，如VPC、安全组等 ...

# 1. 定义OSS Bucket作为数据湖
resource "alicloud_oss_bucket" "data_lake" {
  bucket = "my-cae-datalake"
}

# 2. 创建CPFS文件系统
resource "alicloud_cpfs_file_system" "hpc_cache" {
  # ... CPFS具体配置 ...
  protocol_type = "lustre"
}

# 3. 创建数据流动任务 (关联CPFS与OSS)
resource "alicloud_cpfs_data_flow" "link_to_oss" {
  file_system_id = alicloud_cpfs_file_system.hpc_cache.id
  source_storage = "${alicloud_oss_bucket.data_lake.bucket}.oss-cn-hangzhou.aliyuncs.com"
  # ... 其他数据流动配置 ...
}

# 4. 创建EHPC集群并挂载CPFS
resource "alicloud_ehpc_cluster" "cfd_cluster" {
  name            = "my-cfd-cluster"
  compute_count   = 0 # 核心：初始节点数为0，通过弹性伸缩策略管理
  # ... 其他集群配置 ...

  # 挂载已配置好数据流动的CPFS
  volume {
    volume_id   = alicloud_cpfs_file_system.hpc_cache.id
    volume_type = "CPFS"
    remote_directory = "/"
    local_directory = "/fsx"
  }
}
```

**部署与销毁命令:**
```bash
# 检查并初始化
terraform init

# 创建集群
terraform apply

# 销毁集群
terraform destroy
```

通过上述IaC实践，无论使用哪家云厂商，复杂的HPC环境都转变为可代码化、版本化管理的“临时资源”，召之即来，挥之即去，完美契合了现代化研发流程对敏捷性和成本效益的极致追求。
