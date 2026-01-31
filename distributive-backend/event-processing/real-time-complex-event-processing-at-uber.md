Resource: https://youtu.be/nncxYGD6m7E

Based on the transcript of the presentation "Scalable Real-time Complex Event Processing at Uber," here is an accurate and comprehensive extraction of the content from start to end.

### Introduction and Mission
The speaker, Sri Chen, a Senior Software Engineer at Uber, introduces the company's mission: to make transportation as reliable as running water everywhere for everyone. Uber operates in 6 continents, 70 countries, and over 400 cities.

### Motivation and Use Cases
Uber is a data-driven company that uses Kafka as a log aggregation system and stream processing platform. They ingest logs from thousands of microservices. The goal is to combine this information to extract business insights in real-time.

Three specific use cases are highlighted:
1.  **Fraud Detection:** Detecting multiple logins from the same IP address within the last 10 minutes allows Uber to ban the IP and prevent abuse.
2.  **Gaming the System:** Detecting when a partner accepts a trip, calls the rider to ask for the destination, and then asks the rider to cancel if they don't like the route. This harms the rider experience and can be detected by analyzing the pattern of events.
3.  **Driver Error/Fraud:** Detecting if a partner clicks "picked up" while their GPS location is far from the actual pickup point. This has financial impacts.

### Abstraction: Complex Event Processing (CEP)
Abstracting away the business details, these use cases represent standard computer science problems:
*   **Windowing:** Counting events within a time window (logins).
*   **Pattern Detection:** Identifying a sequence of specific events.
*   **Filtering:** Checking conditions (GPS location vs. status).

To avoid manually coding, testing, and maintaining individual pipelines for each case, Uber sought a declarative semantic (similar to SQL for batch processing) for real-time streams. The solution is **Complex Event Processing (CEP)**, a technology used for over a decade in industries like finance, airlines, healthcare, and energy to combine data sources and infer patterns.

### Technology Stack: WSO2 Siddhi
Uber chose the **Siddhi** CEP engine from WSO2 because:
*   It is lightweight and extensible.
*   It is open-source.
*   It is a Java library, making it compatible with Uber's existing Java/Scala stream processing frameworks (like Samza).

**Features of Siddhi:**
*   Supports filters, joins, aggregations, group by, windows, patterns, sequences, event tables, and user-defined functions (UDFs).
*   **SiddhiQL:** A declarative query language. For example, the fraud use case is written as a query that selects from a login stream, applies a 10-minute sliding window, groups by IP, counts logins, and inserts results into an output stream if the count exceeds ten.
*   **Execution:** At runtime, the engine parses the query into an execution plan and processes events accordingly.

### Scalability and Integration
To make CEP scalable at Uber's level, they integrated Siddhi with **Apache Samza**, a distributed stream processing framework originally from LinkedIn. Samza provides scalability, built-in state management, and fault tolerance with at-least-once guarantees.

To make the output useful, the system supports a generalized set of actions to integrate with the company ecosystem:
*   **RPC/Webhooks:** Calling external microservices or HTTP endpoints.
*   **Storage:** Indexing data into Elasticsearch or Cassandra for analytics.
*   **Kafka:** Writing data back to Kafka for further processing.
*   **Alerting:** Sending metrics to StatsD/Grafana, or notifications via email/push for human operators.

### Architecture Overview
The system comprises two main components:
1.  **RESTful Backend:** Stores query and action logic in MySQL and provides a web UI for users to specify their logic.
2.  **Data Pipeline:** Runs in YARN and consumes messages from Kafka. It consists of three major processors:
    *   **Partitioner:** Similar to the Map stage in MapReduce. It partitions events based on keys and supports predicate pushdown to filter events early.
    *   **Query Processor:** The main CEP engine (Siddhi). It parses queries into execution plans and processes events. It utilizes Samza’s built-in **RocksDB** to checkpoint the CEP engine state periodically for fault tolerance.
    *   **Action Processor:** Executes the actions (e.g., RPCs) defined for the output events. It implements a retry mechanism to ensure at-least-once delivery.

### DAG Generation and Deployment
The system automatically generates the Samza stream processing topology (DAG) by analyzing the user's Siddhi queries:
*   **Simple Logic:** Translated into a graph with just Query and Action processors running in parallel.
*   **Complex Logic:** (Joins/Windows) Translated into a graph that requires the Partitioner stage first, followed by Query and Action processors.

Crucially, no processing logic is hardcoded in the processors. Logic is loaded from the external database via the REST API. If the logic changes but the topology does not, updates are loaded at runtime without redeployment. This unified architecture allows a single monitoring template to cover over 100 production use cases processing 30+ billion messages per day.

### Limitations
1.  **Out-of-Order Events:** Currently not handled. It is assumed events from the same user arrive close together. If needed, Siddhi's K-slack extension can be used.
2.  **Auto-Scaling:** Currently requires manual re-partitioning of Kafka topics and manual tuning of container memory. Future work involves auto-scaling based on CPU, memory, and I/O.

### Technical Challenges and Solutions
1.  **Checkpointing Large State:** Siddhi's state can be large, but Samza limits checkpoints (via Kafka) to 1MB.
    *   *Solution:* Slice the snapshot into smaller pieces, checkpoint them to Kafka, and reconstruct the state upon recovery.
2.  **Snapshot Latency:** Samza historically used a single-threaded model, causing long pauses when writing large checkpoints.
    *   *Solution:* Multi-threaded support is being adopted from the open-source community.
3.  **Exactly-Once Processing:** Currently, there is no solution for exactly-once state processing because Samza cannot commit state and Kafka offsets atomically; system relies on at-least-once guarantees.
4.  **Extending Logic:**
    *   *Solution:* Common functions (String matching, Geo) are implemented as Siddhi extensions loaded at compile time. Ad-hoc logic is handled via UDFs written in JavaScript or Scala.
5.  **Intermediate Kafka Load:** Repartitioning creates heavy load on Kafka.
    *   *Solution:* Encode and compress intermediate messages to reduce the footprint.
6.  **Multi-Tenancy:** Older versions used thread pools allowing unbounded CPU usage per container.
    *   *Solution:* Newer versions use a single thread for main processing, bounding CPU consumption and allowing happy coexistence of multiple jobs in YARN.
7.  **Job Upgrades/Downtime:** Restarting a Samza job can take minutes (resource allocation, state restoration).
    *   *Solution:* Use a replication strategy. Start a "shadow" job -> Upgrade the shadow -> Switch primary traffic to shadow -> Upgrade primary -> Switch back. This achieves zero downtime but requires double capacity during the upgrade.

Q: This architecture is from five years ago. Has it changed? Is it still scallable? What would the architecture look like today?

A:
**Has it changed?**
Yes. Uber eventually replaced much of this custom "Siddhi on Samza" stack with **AthenaX** (based on **Apache Flink**). The industry has largely standardized on Flink for robust stateful processing over Samza.

**Is it scalable?**
**Yes.** Samza is scalable, but the operational complexity of managing checkpoints (RocksDB) manually via Kafka without atomic guarantees was a pain point.

**What would the architecture look like today?**
1.  **Flink SQL:** Instead of SiddhiQL (niche), we use **Flink SQL** which supports `MATCH_RECOGNIZE` for pattern detection (CEP) natively.
2.  **State Management:** Flink handles the "large state" problem automatically with asynchronous RocksDB checkpointing to S3, removing the 1MB Kafka limit hack.
3.  **Exactly-Once:** Unlike Samza's "at-least-once" (in this era), modern Flink provides **Exactly-Once** semantics end-to-end, critical for fraud detection and billing use cases.

## Principal Architect's Q&A

**Q: Complex Event Processing (CEP) sounds hard. Do I really need Flink?**

**A:** Flink is the "Nuclear Option".
1.  **SQL is King**: Do not write Java/Scala jobs if you can avoid it. **Flink SQL** allows you to write `SELECT * FROM Stream MATCH_RECOGNIZE (...)` to detect fraud patterns. It's readable and maintainable.
2.  **Materialized Views**: Often, you don't need a CEP engine. You need a **Materialized View Engine** (like **Materialize** or **RisingWave**). These are databases that "tail" Kafka and keep a SQL view up-to-date in real-time. If your problem is just joins and aggregates, use them instead of Flink.
3.  **The "Lambda" is Dead**: Don't build separate Batch and Speed layers. Flink (and Iceberg) allows **Kappa Architecture**—one codebase handles both historical backfill and real-time streams.