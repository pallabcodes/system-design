Resource: https://www.youtube.com/watch?v=WuRazsX-MBY

Based on the transcript of the presentation "How Netflix Handles Data Streams Up to 8M Events/sec" by Peter Bacchus, here is an accurate and detailed extraction of the content from start to end.

### Introduction and Background
Peter Bacchus, a member of the Real-Time Data Infrastructure team at Netflix, begins by gauging the audience's roles (data science, engineering, infrastructure). He outlines his background at Yahoo, PayPal, and startups, noting his focus on distributed systems and large-scale infrastructure.

**Keystone and the "Paved Path" Philosophy**
Bacchus introduces "Keystone," Netflix's common data pipeline. He explains the Netflix philosophy of the "Paved Path": the infrastructure team provides a supported, standard way for engineers to perform tasks so they don't have to build infrastructure themselves. However, adhering to Netflix’s culture of "Freedom and Responsibility," engineers are free to go "off-road" if the paved path doesn't meet their needs, though they risk getting stuck without support. The goal is to optimize for agility rather than solely for efficiency.

### Scale and Scope
Bacchus jokes that Netflix is often described as "a logging company that occasionally streams movies". He presents the operational metrics for their data pipeline:
*   **Ingestion:** Over 600 billion events per day.
*   **Peak Traffic:** 11 million events per second (approx. 24 GB/sec).
*   **Volume:** Over 1.3 petabytes per day.
*   **Holiday Peak:** During the holidays, ingestion hit 1 trillion events per day.

These events include session traces, UI activities, and business events used for recommendations and A/B testing, but exclude operational metrics (which are handled by a separate system called Atlas).

### Pipeline Evolution
**The Legacy Pipeline**
Originally, the pipeline was simple: applications produced events collected by Chukwa, which wrote them to S3 for offline processing.

**The Branching Problem**
As demand for real-time and "at-least-once" delivery grew, the team introduced a branch off the main line. Traffic was routed into Kafka, then to Elasticsearch, secondary Kafka clusters, or custom consumers like Spark or Mantis (Netflix’s in-house stream processing system). This resulted in duplication of functionality and confusion for producers regarding where to send events.

**The New Keystone Architecture**
To simplify this, the team flattened the architecture. The new design consists of:
1.  **Fronting Kafka:** Handles fan-in.
2.  **Routing Service:** A separate service (Samza-based) that handles fan-out.
3.  **Sinks:** Destinations like S3, Elasticsearch, or secondary Kafka streams.

The team chose to build upon Kafka due to its large community, rather than building a custom solution, despite the challenges of running Kafka in AWS compared to a physical data center.

### Producer and Client Design
Netflix wraps the standard Kafka producer to integrate with their ecosystem (like Eureka) and enforce specific philosophies.
*   **"Drop, Don't Block":** The pipeline must never block an application. If the data pipeline fails, the customer's movie streaming experience must not be affected.
*   **Buffering:** The client provides a local buffer. If the buffer fills during an outage, new messages are dropped.
*   **Resiliency:** Restoration of the service requires no action from the client application; it automatically resumes sending.

Bacchus notes they are currently discussing the "value of data," acknowledging that not all events are equal (e.g., billing events vs. trace logs) and exploring different classes of service.

### Fronting Kafka Architecture
**Cluster Configuration**
To minimize the "blast radius" of failures, Netflix runs **eight clusters per region** rather than one massive cluster.
*   **Isolation:** Each cluster has its own Zookeeper cluster to prevent leader re-election issues from taking down the entire ingestion layer.
*   **Capacity:** Each cluster generally holds under 200 nodes and around 10,000 partitions.
*   **Purpose:** The fronting Kafka acts as a buffer, with a retention period of 8 to 24 hours. This allows time to resolve downstream outages (e.g., S3 or Router issues) without data loss.

**Resiliency and Infrastructure**
*   **Replication:** Currently 2 copies, but they are moving to a model where users select 1, 2, or 3 copies based on priority.
*   **Hardware:** They use **d2.xlarge** instances (balancing cost and performance).
*   **Availability:** Replication is zone-aware. They can lose an entire Availability Zone (AZ) or perform maintenance by removing an AZ without service interruption.
*   **Failover:** They automate region failover and routinely practice failing out of regions or killing brokers (Chaos Monkey) to ensure readiness.

### The Routing Service
The Routing Service is responsible for moving data from the fronting Kafka to the various sinks.
*   **Technology:** It uses **Samza** running in Docker containers, with MySQL as the source of truth for configuration.
*   **Scale:** They run approximately 13,000 containers across 1,300 hosts.
*   **Workload Split:** Approximately 7,000 containers for S3, 4,500 for Kafka, and 1,500 for Elasticsearch.
*   **Shift to Real-Time:** Bacchus notes a shift from a 15-20% real-time workload a year ago to a roughly 55/45 split (Offline/Real-time) now.

### Wire Protocol and Data Formats
Netflix uses a custom wire protocol (invisible to source and sink) that injects metadata like UUIDs, timestamps, and host info.
*   **Format:** Currently JSON, with a planned move to Avro.
*   **Migration Lesson:** Changing the wire protocol during the migration to the new pipeline caused downstream compatibility issues, adding weeks to the project timeline. Bacchus advises minimizing moving pieces during major migrations.
*   **Event Size:** Legacy limit is 10 MB, but they aim to reduce this to 1 MB, as the average payload is only a few kilobytes.

### Operational Insights and Challenges
*   **D2 Instances:** They initially faced issues with instance placement and density on AWS d2.xlarge instances but worked with Amazon to resolve them. They are investigating EBS and larger instance types to reduce "noisy neighbor" issues.
*   **Data Loss:**
    *   **Producer-to-Broker:** This is where the majority of loss occurs (0.0001%), often due to buffer overflows or network errors.
    *   **Router:** Loss is unlikely unless the 8-24 hour retention window is exceeded.
*   **Duplicates:** Can occur at the router level if a job dies before committing offsets (at-least-once delivery).
*   **Latency:** S3 sink latency is ~3 seconds; Real-time/Elasticsearch is ~1 second.

### Monitoring and Tooling
Bacchus highlights the importance of visibility:
*   **Kafka Auditor:** A tool (planned for open source) used for broker monitoring and heartbeating.
*   **Dashboards:** They provide self-service dashboards showing data flow, loss rates, and cluster health (visualized as green/red indicators).
*   **Alerting:** Alerts trigger if message drops exceed 1% or if routing lag exceeds 0.1%.

### Future Roadmap
*   **Messaging as a Service:** Providing a general-purpose pub/sub service for the company.
*   **Stream Processing as a Service:** Building a multi-tenant environment where users can submit processing jobs (joins, filters) without managing the underlying infrastructure.
*   **VPC Migration:** Moving to AWS VPC for better network performance.

### Q&A Highlights
*   **Why Samza?** They chose Samza over Spark Streaming because, at the time, Spark did not handle back pressure well, whereas Samza handled checkpointing and back pressure effectively.
*   **Batching:** They utilize batching at the producer level to reduce CPU and network burden.
*   **Sticky Partitioning**: Used to ensure clusters remain balanced.

## Principal Architect's Q&A

**Q: This guide describes Netflix Keystone (2016). What changed in 2025?**

**A:** The core principles (At-Least-Once, Fronting Kafka) remain, but the "Sink" has evolved.
1.  **Keystone -> Data Mesh**: Netflix now emphasizes a "Data Mesh" where teams own their data products, rather than a central Keystone team owning one massive pipeline.
2.  **Iceberg Tables**: S3 is no longer just a "Dump". They use **Apache Iceberg**. The stream writes to Iceberg tables, providing ACID transactions on S3. This unifies Streaming and Batch (Kappa Architecture).
3.  **Consolidation**: "Router" layer (Samza) is often replaced by **Kafka Connect** or managed Flink for simpler maintenance.