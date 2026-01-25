Resource: https://www.youtube.com/watch?v=1vLMuWsfMcA

Based on the provided transcript, here is an accurate and comprehensive extraction of the video "Lessons learned form Kafka in production" by Tim Berglund.

### Introduction and Role
The speaker is Tim Berglund from Confluent, a company that supports Apache Kafka and builds a streaming data platform and proprietary extensions based on the open-source software,. He leads the developer relations team, which is responsible for training, curriculum, documentation, evangelism, and community outreach.

### The Big Picture: Streams and the Kafka Worldview
The presentation aims to outline the "Kafka worldview," which holds strong opinions on architecture, specifically regarding streams. While people are accustomed to putting data into databases and querying it later, Kafka views all data as **event streams**. Software fundamentally processes events, whether they are requests, sensor readings, or transactions.

*   **Examples of Events:**
    *   **Requests:** A JSON object representing a user looking for a product detail is typically parsed and turned into a SQL query. Kafka views this request itself as an event.
    *   **IoT/Sensor Data:** Car companies are interested in internet-connected vehicles generating events from numerous sensors.
    *   **Logs:** Log files are essentially immutable events. Streaming architecture becomes exciting when operational data (logs) intersects with business data (user activity) in the same pipeline,.

*   **Table-Stream Duality:** A database table is a collection of key-value pairs. Modifications to a table over time (mutations) are effectively a stream of messages. For example, "put value 1 at key 1" followed by "put value 2 at key 2" are messages in a log. Therefore, a table and a stream are isomorphic,,.

*   **Architecture:** The historic approach involves messy point-to-point connections between applications and databases. Kafka proposes a single streaming platform where all data pipelines become one stream of events,. This allows for flexibility; for example, a search service can pull messages off the event stream and dump them into an Elastic Search cluster as a secondary database,.

*   **Forward Compatibility:** Using a streaming platform makes systems forward compatible. If an application sends "product view" messages to a topic currently used by Hadoop for analytics, it is easy to add new services later (like security or recommendation engines) to listen to that same message stream without changing the existing architecture,.

### Apache Kafka Internals
To understand production issues, one must understand how Kafka works. The ecosystem consists of **producers**, the **Kafka cluster**, and **consumers**,.

*   **The Log:** The fundamental data model is a message queue functioning as a log. It is immutable; producers append to the end,.
*   **Topics:** A topic is a named collection of messages.
*   **Distributed System:** Unlike traditional single-master message queues, Kafka is distributed. While this introduces complexity, it is necessary for scale,.
*   **Ordering Compromise:** The major compromise in Kafka is **ordering**. A topic is a "partitioned log," spread across multiple brokers (computers). Global ordering is impossible in a partitioned system; ordering is only preserved *within* a partition,.
*   **Consumer Groups:** These allow partitions to be divided among multiple consumers (servers/threads). If a topic has multiple partitions, a consumer group ensures they are divvied up so that every partition is consumed by one consumer in the group,.
*   **Performance:** Because it utilizes a log abstraction (appending to files), Kafka achieves file system performance with constant-time writes, allowing for high throughput on commodity hardware.

### Q&A Session Highlights
*   **Guarantees:** Kafka provides strict ordering within a partition and persistence via replication,.
*   **Jepsen Tests:** A specific question was raised about Kyle Kingsbury’s Jepsen test from 2013 (version 0.8) showing write loss during split-brain scenarios. Berglund acknowledged that distributed systems can break but noted he did not have details on tests since 2013,.
*   **Rewinding:** Consumers can rewind to get data retrospectively, subject to the retention policy. The default retention is seven days, but it can be set to "forever" (as done by The New York Times),.

### Real-Life Production Lessons
Berglund presented three support scenarios encountered by Confluent.

**1. The "In-Sync Replica" (ISR) List Shrinkage**
*   **Context:** Partitions have a leader and multiple followers (replicas). "In-Sync Replicas" (ISRs) are those caught up with the leader,.
*   **The Problem:** In a real-world scenario, the ISR list shrank (replicas fell behind) and did not recover.
*   **The Cause:** The administrator had upgraded *one* broker to a newer version of Kafka. This new version fixed a performance bug, making that single broker faster than the others. Consequently, the older, slower brokers could not keep up, keeping the ISR list permanently small.
*   **Lesson:** Monitor the ISR list and do not upgrade brokers individually; roll upgrades across the cluster,.

**2. Automation and Cluster Bouncing**
*   **Context:** A customer using Docker set up an automated health check that opened a socket to the producer port. If it failed, it tore down the container and spun up a new one.
*   **The Problem:** A broker kept failing and restarting. The team decided to bounce (restart) the entire cluster.
*   **The Surprise:** Bouncing the cluster took significantly longer than expected (several minutes) because the cluster had a massive number of partitions. More partitions equal more throughput but slower startup/shutdown times.
*   **The Root Cause:** The node was actually fine; a router configuration issue prevented the automation tool from connecting to the broker, causing the tool to kill healthy nodes.
*   **Lesson:** Automation is a "sharp knife" that can hurt you if not used carefully.

**3. Partition Migration Failure**
*   **Context:** A customer added new servers and needed to move partitions using the `kafka-reassign-partitions` tool. This tool has a "generate" mode (creates migration JSON) and an "execute" mode.
*   **The Problem:** The process worked in staging, but when they ran the "generate" command in production, the cluster slowed to a halt and violated SLAs.
*   **The Cause:** The "generate" command calculates based on the number of partitions. The production cluster had orders of magnitude more partitions than staging. Running this expensive operation on a live production system overwhelmed it.
*   **Lesson:** Pay attention to scripts and differences between staging and production environments. Berglund noted Confluent offers an "Auto Data Balancing" feature to handle this more safely.

### Conclusion
The talk concluded with Berglund encouraging the audience to join their Slack channel or download Confluent software to learn more.