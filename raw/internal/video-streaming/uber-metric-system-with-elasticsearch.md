Resource: https://youtu.be/u82r_eqUaiI

Based on the provided transcript, here is an accurate and comprehensive extraction of the presentation "Scaling Uber's Metric System from Elasticsearch to Pinot," covering the content from start to end.

### Introduction and Speakers
The presentation is delivered by Yupong, a Principal Engineer leading the Real-time Data Platform and a Pinot committer, and Nan, a Staff Engineer from the Mobility and Platform team in charge of Uber’s Business Metric System. They aim to discuss the evolution of Uber's metric system (uMetric), the journey from Elasticsearch to Apache Pinot, and their contributions to the open-source software.

### The Need for a Unified Metric System
**Data-Driven Decision Making**
Uber relies heavily on data for decision-making. For example, a trip from Uber HQ to San Francisco has a price calculated by a dynamic pricing algorithm based on supply and demand over the last 10 minutes. Promotion budgets are also determined by data analysis, resulting in the final price seen by the user.

**The Problem of Silos**
Various teams (Data Science, Product Management, Ops) use metrics like trip number, gross booking value, and supply hours. Historically, every team created their own version of business metrics using their own pipelines. This led to "apples to oranges" comparisons because different teams used slightly different logic for metrics like "completed trips". In Uber's use case, precision is critical; a 1-2% discrepancy can turn a profitable business segment into a loss.

**The Solution: uMetric**
Uber developed **uMetric**, a unified metric platform to manage the full lifecycle of metrics: definition, discovery, computation, verification, storage, and serving. Centralization allowed for guaranteed data quality, SLAs, and improved query computation performance.

### Initial Architecture: Elasticsearch (2014–Present)
**The Stack**
The initial architecture ingested data from Kafka (user devices/real-time systems) into Flink pipelines for computation (filtering/aggregation). Data was stored in **Elasticsearch**, and periodically dumped via Spark to Hive for long-term analysis. Users consumed data via a query layer.

**Why Elasticsearch was chosen in 2014:**
1.  **Operability:** Uber had a small team and lacked the expertise to manage OLAP systems like Druid or ClickHouse.
2.  **Upsert Support:** Uber’s trip tables require strong upsert capabilities because trip states (created, assigned, pickup, completed) update continuously.
3.  **Aggregation & Scalability:** Needed support for aggregation and linear scalability.

**Scale of the System**
The system grew to store **1.5 petabytes** of data comprising **4.5 trillion documents**. It handles **1.3 million writes per second** and **700 million scans per second**.

### Optimizations for Elasticsearch
The native Elasticsearch framework could not handle this scale, so Uber implemented several optimizations:

1.  **Sharding Strategy:** Default sharding causes inefficient full index scans. Uber built a system to analyze query history, discover keys (e.g., City), and logically partition tables to avoid full scans.
2.  **Circuit Breaker:** In 2015/2016, Elasticsearch only supported circuit breaking based on payload size. Uber added functionality to check result memory usage to kill queries before they crashed the cluster.
3.  **Dynamic Rate Limiting:** Flink job restarts could cause traffic spikes (10x normal load), crashing clusters in seconds. Uber added a rate limiter to the Elasticsearch sink. It is "dynamic" because it senses cluster health: if healthy, it lifts the limit to recover lag; if unhealthy, it slows down writing.
4.  **Roll-ups:** Since Elasticsearch (prior to 8.x) lacked native roll-ups, Uber created a framework to pre-compute roll-up tables, avoiding scans on large raw tables.
5.  **Caching:** Real-time caching is difficult due to frequent invalidation. However, for dashboards not requiring second-level freshness, Uber built a cache layer with a 1-hour Time-To-Live (TTL).
6.  **Parallel Backfill:** To address data loss or corruption without waiting days to recompute from source, Uber leveraged the fact that data copies exist in other healthy clusters. They built a service to run Elasticsearch re-indexing in parallel (with auto-retry), achieving performance 30 times better than the native single-threaded re-index API.

### The Breaking Point and Migration Decision
Despite optimizations, challenges persisted:
*   **Reliability:** Frequent cluster overloads caused SLA breaches and minor data loss with limited mitigation options other than expensive failovers or adding hardware. Root causes were often impossible to find.
*   **Scalability:** The ROI on scaling was low; they had to add 50-60% more hardware just to maintain reliability.
*   **Engineering Cost:** High maintenance for the optimization tools and heavy on-call loads.

Uber decided to migrate to a true OLAP system. Since **Apache Pinot** was already widely used at Uber, they chose to migrate uMetric to Pinot.

### Migration Challenges and Solutions
**Bridging Feature Gaps**
1.  **Upsert:** Not natively supported in OLAP systems at the time. Uber worked with the Pinot team to add full document upsert support and partial upsert logic.
2.  **Backfill & Connectors:** Pinot lacked a Flink connector for direct writing and a Spark connector for dumping data to Hive. Uber added these.
3.  **Nested Columns:** Pinot supports only flat columns. Supporting nested columns natively required too many changes.
    *   *Workaround:* Uber flattened the schema for Pinot. Since users access data via metrics, they don't see the schema change. For Hive users who need the nested structure, the dump process massages the flat Pinot data back into the nested schema using a stored config map.

**Safe Migration Strategy**
Migrating hundreds of tables and thousands of metrics required a safe approach.
1.  **Shadow Testing:** They built a system to compare Elasticsearch and Pinot for every query on three dimensions: Query Performance (duration), Data Quality (value discrepancy), and Reliability (load increase).
2.  **Draining System:** A powerful traffic routing system allowed them to switch traffic based on table, metric, user, or retention. For example, queries for the latest month's data could go to Pinot, while older data still went to Elasticsearch.

**Results**
The migration improved reliability (fewer incidents), resolved scalability bottlenecks, reduced engineering overhead by deprecating old optimization tools, and lowered on-call load.

### Apache Pinot at Uber
**Overview of Real-Time Analytics (RTI)**
Yupong explains that Uber uses Pinot for three categories of real-time analytics:
1.  **User-Facing Analytics:** e.g., "Restaurant Manager" dashboard showing missing orders to owners.
2.  **Time-Sensitive Decisions:** e.g., Balancing supply and demand in fulfillment systems.
3.  **User Engagement:** e.g., Driver scorecards showing real-time performance feedback.

**Pinot Architecture**
Pinot is a fast, distributed OLAP system originally built by LinkedIn.
*   **Structure:** Tables consist of multiple segments distributed across servers (share-nothing architecture).
*   **Scalability:** It scales horizontally; adding servers increases throughput and availability.
*   **Components:** Uses Helix for cluster management (controller) and separates real-time and offline servers for ingestion.
*   **Performance:** Built on LSM (Log-Structured Merge-tree) architecture, providing sub-second data freshness and <100ms query latency.

Uber built a platform called **River** (Tier-0 availability) to manage Pinot, offering self-service onboarding via a UI called **uWork** and Presto integration via **Neutrino**.

### Uber’s Contributions to Pinot
Uber bridged several gaps to make Pinot viable for their metric system:

1.  **Upsert Support:**
    *   Pinot relies on immutable segments, making updates difficult.
    *   Uber contributed the Upsert feature. It allows tracking order status changes (e.g., Created -> Ongoing -> Delivered) by maintaining a lineage of where records reside to derive the current view.

2.  **Complex Type Support:**
    *   Pinot natively supports primitive types (long, integer, string) for speed.
    *   uMetric required Maps and Arrays. Uber implemented support via two methods: converting to JSON (using JSON indexing) or a rule-based translation to write objects on the fly.

3.  **Connectors:**
    *   **Spark Connector:** Improved performance using gRPC for dumping data from Pinot to Hive.
    *   **Flink Connector:** Enabled backfilling for upsert tables.
    *   **Unified Pipeline Vision:** Uber aims to unify batch and streaming. Instead of writing separate Flink (stream) and Spark (batch) jobs, they want a single Flink job that can run in streaming mode over Kafka or batch mode over Hive.

### Future Work
Uber plans further improvements:
*   **Star-Tree Index:** Leveraging Pinot’s native Star-Tree index to replace custom pre-aggregation/roll-up pipelines.
*   **Isolation & Tiering:** Improving cluster isolation for safer deployments.
*   **Upsert Optimizations:**
    *   **Compaction:** Background threads to compact segments by removing old history of mutable records to save space.
    *   **TTL (Time-To-Live):** Recognizing that upserts are often only needed for the duration of a session (e.g., a few hours). They propose keeping the upsert logic active only for a set TTL to release memory resources for older, immutable records.
