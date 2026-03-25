Resource: https://youtu.be/K-fI2BeTLkk?list=TLGGbN-90c8zw84yNTAxMjAyNg (Real time infra at Uber)

Based on the transcript of the presentation "How Uber scaled its Real Time Infrastructure to Trillion events per day" by Ankur and Mingmin, here is an accurate and comprehensive extraction of the content from start to end.

### Introduction and Scope
Ankur and Mingmin, Senior Software Engineers at Uber’s streaming team, present their journey of scaling Uber’s infrastructure to handle a trillion messages a day.
*   **Use Cases:** Uber relies heavily on real-time processing for matching riders with drivers, calculating fares, and sharing status.
    *   **App Data:** Rider and driver apps emit thousands of data points processed via Kafka to calculate ETAs and matches.
    *   **UberEats:** Calculating reliable food ETAs is complex, involving restaurant status, dish type, and traffic. This requires real-time data collection and machine learning models updating on the fly.
    *   **Fraud Detection:** Requires immediate processing to catch issues before a trip concludes.
*   **The Hub:** Apache Kafka acts as the hub of Uber's data. It is used for general Pub/Sub between microservices, stream processing (Flink/Samza), offline processing (Hadoop/S3), database change logs, and logging.

### Scale
Uber processes over a **trillion messages per day**. This averages 10 million messages per second, with higher peaks. They handle more than a petabyte of data daily across tens of thousands of topics, driven by organic message growth.

### Architecture Overview
The architecture feeds data from apps and databases into Kafka, which is then pulled by search, logging dashboards, real-time engines, and offline storage.
**Requirements:**
*   Horizontal scalability.
*   Client-side latency under 5 milliseconds.
*   Availability of at least "four nines" (currently achieving five nines).
*   Durability guarantees ranging from general use to 100% for financial data.
*   Support for multiple data centers and five languages: Java, Go, Python, Node.js, and C++.
*   Auditing capabilities for data loss.

**Infrastructure Components:**
*   **Regional Kafka Clusters:** The central piece in each data center.
*   **Rest Proxy:** Used to decouple applications from Kafka clusters.
*   **Proxy Client:** Tightly coupled with the Rest Proxy.
*   **uReplicator:** A homegrown version of MirrorMaker used to aggregate data from multiple data centers.
*   **Secondary Clusters:** Fallback clusters used if primary clusters fail.
*   **Local Agent:** A backup system running on hosts to buffer data if the Rest Proxy fails.

### Design Philosophy: Aggressive Batching
To achieve their scale, Uber implemented aggressive batching and asynchronous processing at every stage.
1.  **Proxy Client:** Accepts a message, acknowledges it immediately (sub-millisecond latency), and buffers it for asynchronous production.
2.  **Proxy Server:** Accepts the batch, acknowledges immediately, splits it based on destination brokers, and re-batches for asynchronous production.
3.  **Kafka Cluster:** Configured with `acks=1`, meaning the leader accepts and acknowledges immediately without waiting for replicas, preventing blocking.

### Detailed Component Breakdown

**1. Regional Kafka Clusters**
Uber tunes clusters differently based on use cases:
*   **Data Clusters:** High throughput, prioritizing durability over latency (blocking is okay to save data).
*   **Logging:** High throughput, non-blocking (data loss is acceptable, halting is not).
*   **Database Change Logs:** Zero data loss allowed, strict sequencing.
*   **Surge Pricing:** Stale data is useless; fast recovery is prioritized over data retention.
*   **High Value:** 100% reliability required.

**2. Rest Proxy**
Uber built their own solution because existing open-source options (Confluent) could only handle ~7,000 QPS per box in their benchmarks.
*   **Optimizations:** They replaced the Jersey layer with a simple HTTP Servlet and removed JSON parsing (moving to "bytes in, bytes out"). These changes increased throughput to **45,000 QPS per box**.
*   **Features:** Added metadata caching (to avoid hitting Zookeeper for every request) and support for fallback clusters.

**3. Proxy Client**
This library supports non-blocking async operations and batching.
*   **Features:** Implements back-off mechanisms if downstream is struggling, auto-discovery of clusters, and multiplexing (writing to multiple clusters transparently).

**4. Local Agent**
To prevent back pressure on applications during outages, Uber built a lightweight process running on every node.
*   It combines a Rest interface with a Kafka log module. If the Rest Proxy fails, the client switches to the Local Agent, which buffers data to the local disk.
*   Once the downstream system recovers, the Local Agent backfills the data.

**5. uReplicator**
Uber replaced Kafka MirrorMaker because it suffered from rebalancing storms (taking 10–15 minutes) when handling 5,000–10,000 partitions.
*   **Solution:** uReplicator replaces the rebalancing logic with **Apache Helix** for resource management. It has been running for two years, scales 10x better than MirrorMaker, and is open-sourced.

### Special Use Cases and Tooling

**1. At-Least-Once Kafka (High Durability)**
For hyper-critical data (e.g., payments), the standard async pipeline is insufficient due to potential data loss in memory or leader failure.
*   **Modifications:**
    *   **Proxy Client:** Sends data synchronously.
    *   **Proxy Server:** Skips batching and passes data through to the Regional Cluster.
    *   **Kafka Clusters:** Configured so the leader only acknowledges after **three replicas** have received the data (Regional and Aggregate clusters).
*   **Trade-off:** This trades latency for 100% durability guarantees.

**2. Chaperone (Auditing)**
Uber built an in-house auditing system called Chaperone.
*   **Mechanism:** It counts messages in 10-minute windows at every stage (Client, Server, Kafka) and sends metrics to a centralized database (Kinja).
*   **Reporting:** A service compares counts across stages. If a mismatch occurs (e.g., Client reports 80k messages, Server reports 50k), it triggers an alert. This system audits tens of thousands of topics for completeness.

**3. Kafka Cluster Balancing**
Kafka does not balance itself automatically. Uber built a tool to analyze partition distribution and disk usage.
*   It generates a partition reassignment plan (JSON) to balance the data load across nodes, ensuring no single pair of nodes shares a disproportionate amount of data.

### Future Work and Q&A
*   **Multi-Zone Clusters:** Deploying single Kafka clusters across multiple data centers for consistency during outages.
*   **Chargeback:** Accounting for resource usage by different teams.
*   **Topic Garbage Collection:** Cleaning up inactive topics to free resources.
*   **Q&A:**
    *   **Balancing:** Currently done on-demand at the disk level, moving toward automation.
    *   **Infrastructure:** Mostly physical servers; virtual machines are being explored for multi-zone clusters.
    *   **Compression:** They use compression (Snappy/Gzip) on their topics.

Q: This architecture is from five years ago. Has it changed? Is it still scallable? What would the architecture look like today?

A:
**Has it changed?**
Yes. Uber's custom "uReplicator" and "Rest Proxy" were built because the open-source ecosystem (MirrorMaker 1.0) was immature in 2016. Today, standard tools have caught up.

**Is it scalable?**
**Yes.** Handling a trillion events is feasible with this sharded, batched architecture.

**What would the architecture look like today?**
1.  **MirrorMaker 2:** Instead of building a custom "uReplicator" with Helix, we would use **MirrorMaker 2.0** (based on Kafka Connect), which solves the rebalancing storm issues natively.
2.  **Standard Proxies:** Instead of a custom Rest Proxy, we might use **Envoy** (with Kafka filters) or standard **Confluent REST Proxy** (which is now much faster than the version cited in the talk).
3.  **Federation:** We might use **Kafka Federation** features or **Cluster Linking** (Confluent) to manage the multi-DC replication without running separate replicator clusters.

## Principal Architect's Q&A

**Q: Should I build a custom REST Proxy for Kafka like Uber did?**

**A:** **No.** That was necessary in 2016.
1.  **Envoy Proxy**: Today, use **Envoy** with the Kafka Filter. It decodes the Kafka protocol at L7 and gives you observability (Prometheus metrics) and ratelimiting out of the box.
2.  **Kafka Connect (HTTP Sink/Source)**: If you just need to dump JSON into a topic, use the standard HTTP connector.
3.  **GraphQL Subscription**: For the "Consumer" side (Push to Frontend), map a Kafka Topic to a **GraphQL Subscription** or Server-Sent Events (SSE) via a gateway, rather than polling a REST endpoint.