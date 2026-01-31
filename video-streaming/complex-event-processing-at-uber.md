Resource: https://youtu.be/nncxYGD6m7E?list=TLGGZlKODy1eghcyNTAxMjAyNg

Based on the provided transcript, here is an accurate and comprehensive extraction of the presentation "Scalable Real-time Complex Event Processing at Uber" by Sri Chen, covering the content from start to end.

### Introduction and Mission
Sri Chen, a Senior Software Engineer at Uber, introduces the company's mission: to make transportation as reliable as running water everywhere for everyone. Uber operates in six continents, 70 countries, and over 400 cities.

### Motivation and Use Cases
Uber is a data-driven company that utilizes Kafka as a log aggregation system and stream processing platform. They ingest logs from thousands of microservices in real-time. By massaging and combining this information, they can extract useful business insights. Chen details three specific examples:

1.  **Fraud Detection:** Detecting multiple logins from the same IP address within the last 10 minutes allows the system to ban the IP and prevent fraudulent users from abusing the system.
2.  **Gaming the System:** Detecting a pattern where a partner accepts a trip, calls the rider to ask for the destination, and then asks the rider to cancel if they are uncomfortable with the route. Detecting this in real-time allows Uber to take action to improve the rider experience.
3.  **Driver Error/Fraud:** Detecting if a partner clicks "picked up" while their GPS location is far from the actual pickup point, which has financial impacts on the company.

### Abstraction: Complex Event Processing (CEP)
Abstracting away the business details, these use cases represent standard computer science problems:
*   **Windowing:** Counting events within a time window (e.g., logins).
*   **Pattern Detection:** Identifying a sequence of events within a window.
*   **Filtering:** Checking conditions (e.g., GPS location vs. status).

To avoid having engineers manually code, test, deploy, and maintain individual pipelines for each case, Uber sought a declarative semantic (similar to SQL for batch processing) for real-time streams. The solution is **Complex Event Processing (CEP)**, a concept used for over a decade in industries like finance (fraud detection), airlines (operation monitoring), healthcare (claim processing/patient monitoring), energy, and telecommunications. CEP allows users to specify logic using declarative rules and query languages.

### Technology Stack: WSO2 Siddhi
Uber chose the **Siddhi** CEP engine from WSO2 for several reasons:
*   It is lightweight and extensible.
*   It is open-source.
*   It is a Java library, making it compatible with Uber's existing Java/Scala stream processing frameworks, specifically Apache Samza.

**Features:**
Siddhi supports filters, joins, aggregations, group by, windows, patterns, sequence processing, event tables, user-defined functions (UDFs), and extensions. It uses a declarative query language called SiddhiQL.

**Example Query:**
Chen presents a query for the "multiple login" use case. Ideally, the query reads from a login stream, applies a 10-minute sliding window, groups by IP, counts the logins, and inserts the result into an output stream if the count exceeds ten. This output stream can then be used to take action in real-time.

**Runtime Execution:**
At runtime, the engine parses the user-specified query into an execution plan and processes events according to that logic.

### Scalability and Integration
To make CEP scalable at Uber's level, they integrated Siddhi with **Apache Samza**, a distributed stream processing framework originally from LinkedIn. Samza provides distributed scaling, built-in state management, and fault tolerance to support at-least-once message processing guarantees.

To make the output useful to the rest of the company, the system supports a generalized set of actions:
*   **RPC/Webhooks:** Calling external microservices or HTTP endpoints.
*   **Storage:** Indexing data into Elasticsearch or Cassandra for real-time analytics.
*   **Kafka:** Writing data back to Kafka for further processing.
*   **Alerting:** Sending metrics to StatsD/Grafana, or notifications via chat services, email, or push notifications to human operators.

### Architecture Overview
The system comprises two main components:
1.  **RESTful Backend:** Stores query and action logic in MySQL and provides a web UI for developers to specify their requirements.
2.  **Data Pipeline:** Runs in YARN and consumes messages from Kafka.

**The Data Pipeline Processors:**
The pipeline consists of three major processors:
1.  **Partitioner:** Similar to the Map stage in MapReduce, it partitions events based on keys and supports predicate pushdown to filter events before they enter the next stage.
2.  **Query Processor:** The main CEP engine (Siddhi). It parses queries into execution plans and processes events. It utilizes Samza’s built-in **RocksDB** to checkpoint the CEP engine state periodically for fault tolerance.
3.  **Action Processor:** Executes the actions defined for the output events. It implements a retry mechanism to ensure at-least-once delivery.

### DAG Generation and Deployment
The system automatically generates the Samza stream processing topology (DAG) by analyzing the Siddhi queries:
*   **Simple Logic:** Translated into a graph with just Query and Action processors running in parallel.
*   **Complex Logic:** (Joins/Windows/Patterns) Translated into a graph requiring the Partitioner stage first, followed by Query and Action processors.

Crucially, no processing logic is hardcoded in the processors. Logic is stored externally in the REST API backend databases. If the logic changes but the topology remains the same, updates are loaded at runtime without redeploying the Samza backend. This unified architecture allows a single monitoring template to cover over 100 production use cases processing over 30 billion messages per day. Use cases include fraud detection, alarm detection, marketing campaigns, promotion monitoring, feedback systems, and analytics.

### Limitations
1.  **Out-of-Order Events:** Currently not handled because events from the same rider or partner are usually seconds apart, making it unlikely to be a major issue. If needed, Siddhi's K-slack extension can be used.
2.  **Auto-Scaling:** Currently requires manual re-partitioning of Kafka topics and manual tuning of container memory. Future plans involve using CPU, memory, and I/O stats to auto-scale the pipeline.

### Technical Challenges and Solutions
1.  **Checkpointing Large State:** Siddhi's state can be large, but Samza limits checkpoints (via Kafka) to a default of 1MB.
    *   *Solution:* They implemented logic to slice the snapshot into smaller pieces, checkpoint them to Kafka, and reconstruct the state upon recovery.
2.  **Snapshot Latency:** Samza historically used a single-threaded model, causing long pauses when writing large checkpoints.
    *   *Solution:* Multi-threaded support is being adopted from the open-source community.
3.  **Exactly-Once Processing:** Currently, there is no solution for exactly-once state processing because Samza cannot commit state and Kafka offsets atomically; the system relies on at-least-once guarantees.
4.  **Extending Logic:**
    *   *Solution:* Common functions (String matching, Geo) are implemented as Siddhi extensions loaded at compile time. Ad-hoc logic is handled via UDFs written in JavaScript or Scala.
5.  **Intermediate Kafka Load:** Repartitioning creates heavy load on Kafka.
    *   *Solution:* Encode and compress intermediate messages to reduce the footprint.
6.  **Multi-Tenancy:** Older versions used thread pools allowing unbounded CPU usage per container.
    *   *Solution:* Newer versions use a single thread for main processing, bounding CPU consumption and allowing multiple jobs to coexist happily in YARN.
7.  **Job Upgrades/Downtime:** Restarting a Samza job can take minutes due to resource allocation and state restoration.
    *   *Solution:* Use a replication strategy. Start a "shadow" job, upgrade the shadow, switch primary traffic to the shadow, upgrade the primary, and switch back. This achieves zero downtime but requires double capacity during the upgrade.

Q: This architecture is from five years ago. Has it changed? Is it still scallable? What would the architecture look like today?

A:
**Has it changed?**
Yes. Uber moved from **Samza** to **Flink** (AthenaX). The industry has consolidated on Flink for CEP.

**Is it scalable?**
**Yes**, but maintaining custom Siddhi extensions is painful.

**What would the architecture look like today?**
1.  **Flink SQL:** Use standard Flink SQL `MATCH_RECOGNIZE` for pattern matching.
2.  **Managed Service:** Use **immerok** or **Confluent Cloud for Flink** to avoid managing the YARN/Kubernetes resource scheduler manually.