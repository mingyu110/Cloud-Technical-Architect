# Real-Time & Batch Data Pipeline Project

This project demonstrates a comprehensive, end-to-end data pipeline solution that integrates both real-time (hot path) and batch (cold path) processing. It is built entirely on a modern, scalable, and open-source technology stack, containerized with Docker for easy deployment and development.

The use case is centered around a typical e-commerce platform, tracking data from a transactional PostgreSQL database through to analytical dashboards.

## Architecture

The core design separates data into two layers: a **Hot Layer** for immediate, real-time insights, and a **Cold Layer** for cost-effective storage and complex historical analysis. This hybrid approach ensures both high performance and cost efficiency.

![Architecture Diagram](./images/architecture.png)

## Features

- **Real-time CDC**: Captures every data change from the source database in real-time without impacting its performance.
- **Hybrid Hot/Cold Storage**: Utilizes ClickHouse's ability to use both fast local storage for hot data and cheap object storage (MinIO/S3) for cold historical data.
- **Stream & Batch Unification**: A single architecture handles both streaming and batch ETL workloads.
- **Scalable by Design**: Every component in the pipeline (Kafka, Flink, ClickHouse, Airflow Workers) can be scaled horizontally.
- **Data-Driven ETL**: The batch processing logic in Airflow is dynamically generated from SQL files, making it extremely easy for data analysts and engineers to add or modify business logic.
- **Containerized**: The entire environment is managed by Docker and Docker Compose, ensuring consistency and simplifying setup.

## Technology Stack

- **Database**: **PostgreSQL**
- **CDC**: **Debezium**
- **Message Broker**: **Apache Kafka** with **Schema Registry** (Avro)
- **Stream Processing**: **Apache Flink** (using Scala)
- **OLAP & Lakehouse**: **ClickHouse**
- **Workflow Orchestration**: **Apache Airflow** (with Celery Executor)
- **Object Storage**: **MinIO**
- **Containerization**: **Docker** & **Docker Compose**

## Project Structure

The project is organized into four main directories, each representing a core component of the pipeline:

```
.
├── airflow-docker/     # Airflow services, DAGs, plugins, and SQL scripts for batch ETL
├── clickhouse-docker/  # ClickHouse server and configuration for hot/cold storage
├── flink-docker/       # Flink cluster, Scala source code, and job management scripts
└── kafka-docker/       # Kafka, Zookeeper, Schema Registry, and Debezium connector setup
```

## Data Flow

### Hot Path (Real-time)

1.  **Capture**: Debezium monitors the PostgreSQL Write-Ahead Log (WAL) and captures row-level changes (INSERT, UPDATE, DELETE).
2.  **Ingest**: The change events are published as Avro-formatted messages to Kafka topics.
3.  **Process**: A Flink job consumes the messages from Kafka, performs real-time deduplication to keep only the latest state of each record, and writes the result to "hot" tables in ClickHouse (stored on local disk).
4.  **Serve**: Real-time dashboards query these hot tables to provide up-to-the-second insights.

### Cold Path (Batch)

1.  **Orchestrate**: A daily-scheduled Airflow DAG triggers the batch ETL process.
2.  **Archive**: The first step moves yesterday's data from the ClickHouse hot tables to "cold" tables, which are storedbacked by MinIO object storage.
3.  **Transform**: The DAG then dynamically generates and runs a series of tasks based on SQL scripts to transform the data from Bronze -> Silver -> Gold layers, creating well-modeled, analytics-ready fact and dimension tables.
4.  **Analyze**: BI tools and data analysts query the Gold tables in ClickHouse for historical reporting and deep analysis.

## Getting Started

Follow these steps to get the entire pipeline running on your local machine.

### Prerequisites

- **Docker** & **Docker Compose**
- **Maven** (for building Flink jobs)
- A **PostgreSQL** client (like `psql` or DBeaver) to set up the initial database.

### 1. Environment Configuration

This project uses `.env` files to manage configuration for each component. You will need to create/update the `.env` file in each of the four main directories:

- `kafka-docker/.env`
- `clickhouse-docker/.env`
- `flink-docker/.env`
- `airflow-docker/.env`

Populate them with your specific configurations (e.g., credentials, hostnames). You will also need to replace placeholder values in configuration files like:
- `kafka-docker/connectors/postgres-connector.json` (database credentials)
- `clickhouse-docker/config/storage.xml` (MinIO credentials)

### 2. Database Setup

1.  Make sure you have a PostgreSQL server running and accessible from Docker.
2.  Create a database (e.g., `ecommerce`).
3.  Execute the following SQL scripts to set up the necessary tables and permissions for Debezium:
    - `ecommerce Table.sql`
    - `Prepare Query for Debezium Access Postgresql.sql` (remember to set your password here)
4.  Optionally, populate the tables with sample data using:
    - `Populate Postgresql Eccomerce Data.sql`

### 3. Start All Services

You can start all services in detached mode. It's recommended to start them in order.

```bash
# 1. Start Kafka, Zookeeper, and Kafka Connect
cd kafka-docker
docker-compose up -d --build

# 2. Start ClickHouse
cd ../clickhouse-docker
docker-compose up -d --build

# 3. Start Flink Cluster
cd ../flink-docker
docker-compose up -d --build

# 4. Initialize and Start Airflow
cd ../airflow-docker
# This init command will set up the Airflow database, user, etc.
docker-compose run airflow-init
# Start all Airflow services
docker-compose up -d --build
```

### 4. Deploy Connectors and Jobs

1.  **Submit Debezium Connector**:
    ```bash
    curl -X POST -H "Content-Type: application/json" \
         --data @kafka-docker/connectors/postgres-connector.json \
         http://localhost:8083/connectors
    ```
    You can now check the Kafka UI at `http://localhost:8081` to see if topics are being created.

2.  **Build and Run Flink Jobs**:
    ```bash
    cd flink-docker
    chmod +x ./initial_run.sh
    ./initial_run.sh
    ```
    This script will build the Scala projects and submit the jobs to the Flink cluster. Check the Flink UI at `http://localhost:8087`.

### 5. Activate Airflow DAG

1.  Navigate to the Airflow UI at `http://localhost:8080` (default login: `airflow`/`airflow`).
2.  Find the `ecommerce_pipeline` DAG and un-pause it to enable the daily batch runs.

Your entire real-time and batch data pipeline is now up and running!
