Resource: https://youtu.be/u6AjSr58h6g?list=TLGGAyr6rvw-G5UyNTAxMjAyNg


Based on the transcript of the presentation "From Zero to a Hundred Billion: Building Scalable Real-Time Event Processing at DoorDash" by Alan Wang, here is an accurate and comprehensive extraction of the content from start to end.

### Introduction and Core Principles
Alan Wang introduces himself as a builder of real-time data infrastructure, formerly at Netflix (Keystone pipeline) and currently at DoorDash building a system called **Iguazu**. He outlines four principles for successful real-time data architectures:
1.  **Decoupling Stages:** Using distinct stages for processing.
2.  **Leveraging Stream Processing Frameworks:** Understanding what they offer and how to pick one.
3.  **Creating Abstractions:** Building tools to facilitate system adoption.
4.  **Fine-Grained Failure Isolation:** Ensuring scalability and preventing bottlenecks.

### Use Cases at DoorDash
Wang details three primary use cases for real-time events:
1.  **Analytical Data:** Reliable transport to the data warehouse (Snowflake) for business analysis. For example, the Dasher assignment team uses this to detect algorithm bugs in near real-time.
2.  **Mobile Health Monitoring:** Integrating mobile events with time-series backends to identify issues in new app releases quickly.
3.  **Sessionalization:** Grouping user events into sessions in real-time to analyze behavior and push recommendations.

### Legacy Systems vs. New Goals
Historically, DoorDash used legacy monolithic pipelines with mixed transports and third-party services, making latency and cost difficult to control. They decided to build **Iguazu** from scratch with specific goals: supporting heterogeneous sources (microservices/mobile), providing low latency ingest to the warehouse, enabling easy access for consumers, and enforcing end-to-end schemas.
*   **Result:** The system scaled from a few billion to hundreds of billions of events per day with a four-nines delivery rate, reducing latency from days to minutes.

### Iguazu Architecture Overview
The architecture flow consists of:
1.  **Ingestion:** Clients send data to the **Iguazu Kafka Proxy**.
2.  **Pub/Sub:** Data lands in **Apache Kafka** to decouple producers from consumers.
3.  **Processing:** **Apache Flink** applications handle transformation via DataStream APIs and Flink SQL.
4.  **Destinations:** Sinks include S3 (Data Warehouse), Redis (Real-time features), and Chronosphere (Operational Metrics).

### Event Producing: The Kafka Proxy
For analytical data, high volume and scalability are prioritized. Minor data loss (less than 0.1%) is acceptable. DoorDash customized the **Confluent REST Proxy** to abstract Kafka complexities.

**Key Features:**
*   **Batching:** To reduce CPU utilization on brokers, the proxy batches events from multiple clients. This trades a small amount of latency for high efficiency.
*   **Multi-Cluster Producing:** The proxy maps topics to specific Kafka clusters, allowing load balancing and migration between clusters.
*   **Asynchronous Request Processing:** The proxy responds to the client as soon as the record enters the producer buffer, without waiting for broker acknowledgment. This reduces back pressure on clients.
*   **Retries:** To mitigate data loss from async processing, the proxy automates retries on randomly picked partitions, keeping data loss below 0.001%.

### Event Consuming: Apache Flink
Wang explains that simple loop-based Kafka consumers are insufficient because they lack offset committing, state persistence, and their parallelism is limited by partition counts.

**Why Flink?**
Flink provides delivery guarantees, checkpointing for state restoration, and flexible resource assignment. DoorDash created a platform where each Flink job runs as a separate Kubernetes service for isolation.

**Abstractions:**
*   **DataStream API:** For engineers needing fine-grained control.
*   **Flink SQL:** For casual users.
*   **Rivera (DSL):** To assist machine learning engineers who need real-time features (e.g., store order counts for ETA prediction), they built a SQL-based DSL called Rivera. Engineers define logic in a YAML file, reducing development time from weeks to hours and code volume by 70%.

### Event Format and Schemas
DoorDash standardized a unified event format containing an **Envelope** (metadata, context) and a **Payload** (schema-encoded properties).
*   **Custom Attributes:** The envelope includes a non-schematized JSON block for flexibility during early development.
*   **Serialization Library:** Handles conversion between Event APIs and Kafka records.
*   **Schema Registry:** They leverage Confluent Schema Registry to enforce contracts using Schema IDs embedded in the payload.
*   **Formats:** They primarily use **Protobuf** (due to gRPC microservices) but support conversion to **Avro** for data framework compatibility.
*   **Build-Time Registration:** To prevent runtime failures caused by incompatible schema changes, schemas are validated and registered during the CI/CD build process via a central repository.

### Data Warehouse Integration (Snowflake)
Integration involves a two-step process to ensure consistency:
1.  **Flink to S3:** A Flink application uploads Kafka data to S3 in Parquet format using streaming file sinks. This decouples processing from Snowflake failures and enables backfills.
2.  **S3 to Snowflake:** **Snowpipe**, triggered by SQS messages, copies data from S3 to Snowflake tables near real-time.
*   **Isolation:** Each event has its own independent pipeline.

### Operations and Automation
To manage the complexity of creating pipelines for every event, DoorDash automated the onboarding process.
*   **Minions Service:** An orchestration service utilizing the Cadence workflow engine and GitHub automation manages Terraform pull requests and infrastructure setup.
*   **Self-Serve UI:** Users can explore schemas and configure Snowpipe integration via a UI, reducing onboarding time from days to minutes.
*   **Notifications:** The system integrates with Slack to update users on onboarding progress.

### Summary of Principles
Wang concludes by reviewing the four principles:
1.  **Decouple Stages:** Use Pub/Sub and Cloud Storage to separate producers, processors, and warehouses.
2.  **Right Framework:** Choose frameworks (like Flink) that support multiple abstractions and data formats.
3.  **Abstractions:** Build proxies, DSLs, and UIs to facilitate adoption.
4.  **Isolation:** Create independent pipelines per event to avoid resource contention and ease scaling.

### Q&A Session
*   **REST Proxy & Data Loss:** The async mode described is for analytical data. For strict durability, the proxy can be configured to wait for broker acknowledgments, though this adds latency.
*   **Flink Alternatives:** Wang recommends Flink over **Akka** for its data processing capabilities. Regarding **Apache Beam**, he notes that sticking to the native framework (Flink) is often more efficient than using the Beam API layer.
*   **Dead Letter Queues:** For bad messages, a Dead Letter Queue is the ultimate solution for eventual reprocessing.
*   **Kafka vs. SNS/SQS:** SNS/SQS is point-to-point. Kafka is preferred for streaming because it supports batching, fan-out to multiple independent consumer groups, and historical replay.
*   **Pulsar vs. Kafka:** DoorDash evaluated **Pulsar** (previously at Netflix) but found it less mature and more complex (requiring Apache BookKeeper) than Kafka. They stuck with Kafka for simplicity.
*   **Schema Registration:** The build-time schema registration discussed applies to the producer side.