Resource: https://youtu.be/K-fI2BeTLkk

Based on the provided transcript, here is a comprehensive extraction of the presentation "How Uber scaled its Real Time Infrastructure to Trillion events per day."

### **Introduction and Agenda**
Anurag and Mingmin, senior software engineers on the streaming team at Uber, present their journey of scaling Uber’s infrastructure to handle approximately one trillion messages per day. Anurag focuses on Apache Kafka and previously built cloud infrastructure at eBay, while Mingmin focuses on distributed data systems and previously worked at Twitter and Salesforce. The agenda covers real-time use cases, the scale of operations, a deep dive into the architecture (including the REST proxy, local agent, and uReplicator), special use cases like reliable messaging and auditing tools, and a preview of future projects.

### **Real-Time Use Cases**
Uber is primarily powered by real-time processing, which facilitates matching riders with drivers, calculating fares, and sharing status updates.
*   **Rider and Driver Apps:** These emit thousands of data points per minute regarding location and status, which flow through Kafka into stream processing systems to calculate matches and Estimated Time of Arrivals (ETAs).
*   **UberEats:** Calculating a reliable ETA for food delivery is a complex engineering problem involving the restaurant's preparation status, the specific dish, traffic conditions, and driver availability. Machine learning models update this data on the fly.
*   **Fraud Detection:** This requires immediate processing to prevent fraudulent trips before they are completed.
*   **Status Sharing:** Data points are processed in real-time to share ETAs with friends.

Apache Kafka serves as the hub for all this data.

### **Kafka Usage and Scale**
Kafka is utilized as a general Publish-Subscribe (Pub/Sub) system for microservices, a feeder for stream processing engines like Samza and Flink, a pipeline for offline processing via HDFS and S3, a mechanism for database change logs, and a transport for logging data.

 regarding scale, the system processes over one trillion messages per day. This averages to 10 million messages per second, with significantly higher peaks. The infrastructure handles more than a petabyte of data daily across tens of thousands of topics.

### **Architecture Overview**
The data stack consists of applications and databases on one side feeding into Kafka, which then distributes data to search, fare calculation, logging dashboards, real-time processing, and offline storage.
**Requirements:**
*   **Horizontal Scalability:** To keep pace with Uber's growth.
*   **Latency:** Client-side latency must be under 5 milliseconds.
*   **Availability:** A promise of 99.99% availability (currently achieving five nines).
*   **Durability:** High reliability for critical data like payments, while tolerating some loss for logging.
*   **Language Support:** Must support Java, Go, Python, Node.js, and C++.
*   **Auditing:** Capability to track data loss across the trillions of messages.

**Infrastructure Components:**
The architecture centers on Regional Kafka Clusters.
1.  **REST Proxy:** A homegrown solution placed in front of the clusters to decouple applications from Kafka.
2.  **Proxy Client:** Tightly coupled with the REST proxy servers.
3.  **uReplicator:** An Uber-built version of MirrorMaker used to move data from regional data centers to aggregate clusters.
4.  **Secondary Clusters:** Fallback clusters used if the primary cluster fails; the REST proxy buffers data here until recovery.
5.  **Local Agent:** A homegrown tool running on nodes to buffer data locally if the REST proxy is unreachable.

**Batching Strategy:**
To achieve scale, the team implemented aggressive batching and asynchronous processing.
*   **Proxy Client:** Accepts a message, acknowledges it immediately to the application (sub-millisecond latency), and buffers it for asynchronous production.
*   **Proxy Server:** Acknowledges the batch immediately, splits it based on destination brokers, and produces asynchronously.
*   **Kafka Cluster:** Configured with `acks=1`, meaning the leader accepts and acknowledges without waiting for full replication, preventing blocking.

**Cluster Tuning:**
Different clusters are tuned for specific use cases.
*   **Data Clusters:** High throughput, but prioritizing data retention over speed if necessary.
*   **Logging:** Prioritizes speed; it is acceptable to drop data to prevent blocking.
*   **Database Change Logs:** Zero data loss tolerance; sequence matters.
*   **Surge Pricing:** Stale data is useless, so the system drops old data to recover fast during issues.
*   **High Value:** Can block for a long time to ensure zero data loss.

### **Deep Dive: Infrastructure Components**

**REST Proxy:**
Uber built a REST proxy to decouple clients and support languages other than Java (which was the only first-class citizen in the Kafka community at the time).
*   **Performance Improvements:** They optimized Confluent's open-source proxy. By replacing the Jersey layer with simple HTTP servlets and removing JSON parsing (handling raw bytes), they increased throughput from 7,000 QPS to 45,000 QPS per box.
*   **Metadata Caching:** They implemented caching for metadata to avoid hitting Zookeeper for every request.
*   **Features:** Added support for fallback clusters and quota management.

**Proxy Client:**
This library implements non-blocking async operations, batching, and a back-off mechanism that responds to signals from the proxy server. It also supports auto-discovery and multiplexing, allowing applications to write to multiple clusters seamlessly.

**Local Agent:**
To prevent back pressure on applications during downstream issues, Uber created the Local Agent. This lightweight process runs on every node, combining the REST interface with Kafka's log module. If the proxy client cannot reach the proxy server, it writes to the Local Agent, which stores data on the disk. Once the system recovers, the Local Agent backfills the data to the REST proxy.

**uReplicator:**
Uber replaced MirrorMaker with uReplicator because MirrorMaker's rebalancing process took 10–15 minutes when handling 5,000–10,000 partitions, causing major issues. uReplicator uses Apache Helix for resource management, solving the rebalancing issue and allowing for 10x scaling.

### **Special Use Cases and Tooling**

**Reliable Messaging (At-Least-Once Kafka):**
For hyper-critical data like payments, the standard pipeline's potential for data loss (e.g., app crashes before sending buffered batches) is unacceptable.
*   **Modifications:** The proxy client sends data synchronously, skipping the batching stage. The proxy server passes data directly to the Regional Kafka Cluster.
*   **Durability:** The Regional and Aggregate clusters are tuned to only acknowledge when three replicas have received the data.
*   **Trade-off:** This trades higher latency for 100% durability guarantees.

**Auditing (Chaperone):**
Chaperone is an in-house auditing system plugged into every stage (client, server, Kafka).
*   **Mechanism:** It counts messages per topic in 10-minute windows and sends these metrics to a Chaperone web service, which aggregates them in a database.
*   **Reporting:** A report service compares counts across stages to detect data loss or latency violations, triggering alerts if mismatches occur.
*   **Accuracy:** Timestamps inside the messages are used to ensure accurate comparisons across stages.

**Cluster Balancing:**
Since Kafka does not self-balance data distribution well, Uber built a tool that analyzes partition sizes on disks. It generates a partition reassignment plan (moving replicas) to ensure even distribution of data across the cluster.

### **Future Work and Q&A**

**Ongoing Projects:**
*   **Multi-Zone Clusters:** Deploying single Kafka clusters across multiple data centers to ensure consistency and durability during outages.
*   **Chargeback:** Accounting for resource usage by different teams for planning.
*   **Topic Garbage Collection:** Automating the cleanup of inactive topics to save resources.
*   **uReplicator Enhancements:** Further improvements to the replication tool.

**Q&A:**
*   **Balancing Logic:** The balancing tool looks at disk usage and solves a scheduling problem to move replicas (not leaders) to balance the load. It currently runs on-demand but will become automatic.
*   **Infrastructure:** They run primarily on physical hardware but are exploring virtual machines for multi-zone clusters.
*   **Compression:** They utilize compression on their topics, specifically Snappy (though the exact comparison to Gzip was detailed in benchmarks not fully recited).