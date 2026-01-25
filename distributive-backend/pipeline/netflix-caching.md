Resource: https://www.youtube.com/watch?v=Rzdxgx3RC0Q

Based on the transcript of the video "Caching at Netflix: The Hidden Microservice" by Scott Mansfield, here is an accurate and comprehensive extraction of the content from start to end.

### Introduction and Context
Scott Mansfield, a senior software engineer on the EVCache team at Netflix, introduces the topic of the "hidden microservice," which is the nickname for their caching layer. He clarifies that this presentation concerns the Amazon Web Services (AWS) Cloud caching layer, not the Open Connect CDN.

He illustrates the user experience: a user signs up, selects a profile (e.g., "Tester"), selects titles they like, and receives a personalized homepage with specific recommendations like "Narcos",. The speed of this experience is critical because Netflix has approximately **90 seconds** to capture a user's attention before they move on to something else. To ensure speed and smoothness, Netflix caches data on the server side across various touchpoints, including login, profile selection, personalization, homepage loading, and box art selection,. A request trace shows that for a single homepage request, the vast majority of backend touches are to EVCache nodes.

### EVCache Overview and Scale
**Definition and Features**
EVCache (Ephemeral Volatile Cache) is a distributed, sharded, and replicated key-value store optimized for AWS and tuned for Netflix's specific use cases,.
*   It is based on Memcached.
*   It is highly resilient to failure (AWS is described as "Chaos Monkey as a Service").
*   It is topology-aware for faster network access.
*   It is linearly scalable.
*   It supports seamless deployments.

**Why Optimize for AWS?**
Optimization is necessary because the environment is highly dynamic: instances, zones, and regions can fail; the network is lossy; and customer requests can bounce between regions,.

**Scale**
The EVCache team (consisting of four engineers) manages:
*   Hundreds of terabytes of data.
*   Trillions of operations per day (millions per second).
*   Tens of billions of items.
*   Thousands of servers (over 10,000) across tens of clusters.
*   Operation across three AWS regions.

### Architecture and Topology
**Connection Structure**
The architecture involves an application using a service client which wraps the EVCache client (a Java JAR). The client connects via TCP to the server side, which runs Memcached and **Prana** (a Java sidecar for non-Java applications and service discovery registration).

**Cluster Topology**
In a single region, a cluster spans three Availability Zones (AZs). There is one full copy of the data per AZ, meaning there are three copies total in the region,.
*   **The Graph:** The connection structure forms a "complete bipartite graph." Every client connects to every server instance. Servers do not talk to each other, and clients do not talk to each other.
*   **Read/Write Logic:** For reading, the client tries the closest server first, with fallbacks to other zones if failures occur. For writing, the client writes to all three copies.

### Use Cases
Mansfield details four primary use cases, ranging from simple to complex:
1.  **Look-aside Cache:** The application checks EVCache first. If the data is missing, it queries the database (e.g., Cassandra) and writes the data back to the cache.
2.  **Transient Data Store:** Used for data like playback session tracking. Multiple apps update the session state in the cache without a backing database.
3.  **Primary Store (Pre-compute):** Large-scale offline systems compute personalized homepages overnight and write them directly to EVCache. Online services read from the cache. Because of Netflix's fallback culture, this is considered acceptable storage.
4.  **High Volume/Availability (UI Strings):** Apps hold an in-memory cache for critical UI strings. They refresh from EVCache. If EVCache is unavailable, the in-memory data prevents a blank UI.

### Personalization and Polyglot Support
**The Pipeline:** Personalization involves a Directed Acyclic Graph (DAG) of data dependencies. Offline systems (Compute A, B, C, etc.) generate data and publish to EVCache. Online services pick and choose data from different parts of this pipeline.

**Polyglot:** While the primary environment is Java, the team supports other languages via the Prana sidecar (REST API). They utilize a remote HTTP API and are experimenting with a Memcached protocol API.

### Advanced Operations: Replication and Warming
To handle scale, EVCache employs Kafka to stream mutation metadata.

*   **Cross-Region Replication:** When an app writes to a cache in Region A, metadata is sent to Kafka. A "Replication Relay" reads this from Kafka and sends it to a "Replication Proxy" in Region B, which writes to the local cache. This works bidirectionally across all regions.
*   **Cache Warming:** To scale a cluster (e.g., from 2 to 4 nodes), a new cluster is spun up. A "Cache Warmer" app reads metadata from Kafka, pulls data from the old cluster, and writes it to the new one until they match. Traffic is then switched to the new cluster.

### Project Moneta: Server Evolution
Mansfield introduces "Moneta" (named after the goddess of memory and funds), a project to optimize costs by storing data on disk (SSD) rather than RAM.

**Motivation**
*   **Cost:** Storing everything in RAM is expensive.
*   **Architecture Shift:** Netflix moved to an "N+1" architecture, allowing traffic shifting between three regions.
*   **Global Expansion:** Launching in 130 new countries increased data volume.
*   **Access Patterns:** Data access is highly region-specific. Hot data is very hot; cold data is very cold. The goal is to keep the working set in RAM (L1) and the full dataset on SSD (L2),.

**Moneta Architecture**
The new server structure runs three processes using the same protocol:
1.  **Rend (L1/Proxy):** A high-performance proxy written in **Go**. It manages connections, orchestrates L1/L2 requests, handles metrics, and implements "parallel locking" to ensure data integrity during concurrent requests,,.
2.  **Memcached (L1):** Standard Memcached used for RAM storage.
3.  **Mnemosyne (L2):** An SSD-backed storage solution. It uses a C++ core wrapping **RocksDB**.
    *   It uses **FIFO compaction** (a queue of files organized by time).
    *   It pins Bloom filters and indices in memory for speed.
    *   It uses multiple RocksDB instances per box to lower latency,.

**Performance and Results**
*   **Ports:** The server exposes different ports for standard traffic (L1/L2 managed) and batch traffic (writes that bypass L1 to avoid polluting the hot set).
*   **Latency:** Average server-side "get" latency is ~230 microseconds. "Set" latency is ~367 microseconds. Client-side response is typically under 1 millisecond,.
*   **Savings:** The project resulted in approximately **70% cost savings** on a single cluster.

### Q&A Session
Mansfield answers several questions from the audience:
*   **Why RocksDB?** It was the fastest option and fit the use case well.
*   **Couchbase?** They prefer their homegrown solution for the ability to customize quickly.
*   **Memcached Protocol Limits?** No major limitations found; users generally fetch whole data blobs.
*   **Time Scale?** The project took about a year from dabbling in Go to production rollout,.
*   **Adopting Go?** A fast proof-of-concept convinced the team, and they have now embraced the language.
*   **Management Driven?** No, the project was engineer-driven based on business context, then pitched to management.
*   **Personalization DAG:** The DAG is ad-hoc in engineers' minds; services locate caches via the Eureka discovery system.
*   **Other Cloud Providers?** No plans; the team focuses on solving Netflix's problems on AWS.