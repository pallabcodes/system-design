Resource: https://youtu.be/rP9EKvWt0zo

Based on the transcript provided, here is an accurate, comprehensive extraction of the presentation "Scaling Redis at Twitter," detailing the speaker's discussion from start to end.

### Introduction and Background
The speaker, a software engineer at Twitter since late 2010, introduces himself as a member of the cache team. He has worked on development, capacity planning, deployment, and diagnosis, functioning effectively as a Site Reliability Engineer (SRE) for two years before the team acquired dedicated SREs.

### Why Twitter Adopted Redis
The speaker explains the specific technical reasons Twitter moved from Memcached to Redis, primarily driven by the "Timeline" service.
*   **The Timeline Problem:** A timeline is an index of tweet IDs chained together. When a new tweet is generated, it fans out to all relevant timelines. Reads and writes are incremental and small, but the timeline object itself is large (up to 3,000 items).
*   **Network Bottleneck:** Using Memcached required reading and writing the entire large object for small updates. If the average object size exceeds 1KB, the bottleneck shifts from the CPU to the network.
*   **Long Common Prefix Problem:** For flexible schemas or metrics observed over time, storing attributes individually creates long common prefixes (e.g., metric names with different timestamps). Storing them individually repeats the prefix, wasting space. Grouping them under a common prefix is more space-efficient.
*   **CPU Utilization:** Dedicated in-memory key-value stores like Memcached often leave the CPU underutilized (using only ~1% for 1,000 requests per second). Redis utilizes this spare CPU capacity to manage complex data structures, which the speaker views as a brilliant insight.

### Redis at Twitter: History and "Haplo"
*   **Timeline Launch:** The timeline team introduced Redis to Twitter, launching it in production in Fall 2011 under the project name "Haplo".
*   **Usage Scope:** It drives the timeline and revenue services.
*   **Storage Philosophy:** Redis is used strictly as a cache. No on-disk persistence features are used because the "storage" team is separate from the "cache" team, and there are specific quirkiness and goals associated with storage that Redis does not meet for them.
*   **Versioning:** Twitter runs a fork of Redis 2.4. They are "stuck" on this version because they added custom features, though the speaker hopes to merge changes upstream.

### Custom Data Structure 1: Hybrid List
The speaker details a custom data structure they built called "Hybrid List" to address memory and latency issues.
*   **The Problem:** Redis `ziplist` is space-efficient but expensive to update (requires `memmove` and `realloc`), while `linkedlist` uses doubly linked pointers, creating significant overhead where metadata size exceeds the data size (integers).
*   **The Latency Trap:** Timelines vary significantly in size. Evicting many small timelines to allocate contiguous memory for one large `ziplist` write can cause high latency, which is exacerbated by the fan-out architecture.
*   **The Solution:** The Hybrid List is a linked list of zip lists. It allows fixed-size thresholds (in bytes) for chunks. If a chunk fills up, it spills over to the next zip list. This ensures memory allocation is predictable.
*   **Scale:** This implementation handles 40TB of allocated heap, serves 30 million queries per second (QPS), and runs on over 6,000 instances in a single data center.

### Custom Data Structure 2: B-Tree
*   **The Problem:** Redis typically requires two data structures for hierarchical keys: a Hashmap for lookups and a Sorted Set for range queries. However, Sorted Sets convert scores to doubles, preventing the use of arbitrary secondary keys.
*   **The Solution:** They ported a BSD implementation of a B-Tree into Redis, creating a "B-Tree Set". This allows both point lookups and range queries within a single data structure.
*   **Performance:** It serves 9 million QPS across 4,000 instances. However, it is a "memory hog" because it lacks the memory optimizations found in structures like zip lists.

### Cluster Management
The speaker identifies cluster management as the primary barrier to Redis adoption. Unlike Memcached, where data is immutable and client-side hashing suffices, Redis operations are not idempotent, making data corruption a risk during network glitches or node failures.

**The Proxy Approach:**
*   **Philosophy:** Twitter favors a centralized view of the cluster state rather than client-side consensus or server-side management.
*   **Implementations:** They use "Twemproxy" (originally for Memcached, adapted for Redis) and other internal proxy solutions based on "Haplo".
*   **Why Proxy?**
    *   **Separation of Concerns:** Keep the server "dumb but fast" (data path) and move complexity to the control path. Embedding cluster management in stateful servers complicates updates (requires restarts).
    *   **Client Complexity:** Updating 100+ distinct clients across a polyglot ecosystem is impossible.
*   **The Latency Myth:** The speaker refutes the idea that an extra network hop via a proxy adds significant latency. Profiling showed that the kernel/network round trip is under 500 microseconds, whereas JVM and library (Finagle) overheads contribute ~10 milliseconds. Optimizing the network hop is irrelevant compared to the JVM overhead.
*   **Reliability:** Proxies are stateless. If one fails, the client connects to another. The global cluster view is managed externally, preventing the "N-squared" agreement problem among proxies.

### Data Insight and Logging
As an acting SRE, the speaker needed to prove to service owners that the cache was not the cause of latency issues.
*   **Logging Strategy:** They implemented a logging module that captures metadata (timestamp, command, key, status, length) but skips the value to avoid privacy/NSA issues.
*   **Performance:** The logger uses no locks and no blocking.
*   **Aggregation:** To handle the bandwidth of logging 100k QPS (which would generate 10MB/s of logs), they perform pre-processing on the box. A process aggregates the logs into summaries (e.g., top 20 keys, traffic spikes) and sends only the summary off the box to storage/visualization systems like Storm.

### Personal Insights and Takeaways
The speaker shares four personal insights (disclaiming that these are not official Twitter views):

1.  **Scale Demands Predictability:**
    *   In large clusters, tail latencies matter significantly because fan-out queries are limited by the slowest shard.
    *   **Containerization Issues:** Redis introduces external fragmentation, unlike Memcached's internal fragmentation. In container environments (like Mesos), users must over-allocate memory buffers to avoid being killed by the scheduler.
    *   **Graceful Degradation:** Services should strictly reject traffic when resource limits are hit rather than crashing or entering garbage collection spirals.
    *   **Mesos Limitations:** Mesos resource policing is too coarse-grained (checking previous time slots), which causes issues for ultra-low latency services like cache where timeouts are set to 20ms.

2.  **Push Computation to Data:**
    *   Hardware trends (many CPU cores, relatively slower network/disk IO) favor performing computation on the server before transferring data.
    *   **Lua Scripting:** While promising, the speaker believes on-the-fly Lua scripting is not production-ready because it introduces unpredictable loads that threaten SLAs. Ideally, scripts should be "deployed" configurations that can be reviewed and benchmarked.

3.  **Redis as Stream Processing:**
    *   The speaker suggests Redis could replace systems like Storm for high-performance stream processing because it already possesses the necessary components: Pub/Sub, routing, and scripting.

4.  **Wish List for Redis:**
    *   Explicit memory management (to avoid OOM issues).
    *   Deployed Lua scripts.
    *   **Multi-threading:** Redis is single-threaded, which makes managing high-memory, multi-core boxes difficult (requiring 50+ instances per host). Multi-threading would simplify cluster management.

### Open Source Philosophy and Challenges
The speaker addresses why Twitter forks code rather than contributing back immediately.
*   **Context/Scale:** Running 1,000 instances creates different problems and priorities than running 10.
*   **Quality Control:** High-quality projects often have a "clandestine figure" (like Antirez for Redis or the NGINX author) enforcing strict standards, which makes contributing difficult.
*   **The C Language:** The lack of namespacing and classes in C makes it hard to share and refactor code cleanly without tight coordination.
*   **Corporate Reality:** Engineers are paid to solve company problems, not community problems. Contributing back takes time away from internal obligations.

### Q&A Session Details
*   **Sharding:** Keys are mapped to abstract "buckets" (integers), and buckets are mapped to physical nodes. Rebalancing involves changing the bucket-to-node mapping.
*   **Replication:** Proxies can be configured to write to multiple replicas and read from one or both (with repair logic).
*   **Failure Handling:** They use a tiered approach. If a primary rack fails, traffic shifts to a backup tier (e.g., a "spillover pool") with short TTLs to absorb the load until the primary returns.
*   **Cost Management:** Project owners are generally responsible for their own caching strategy, but the cache team works closely with large users (500+ nodes) to optimize usage. They discourage caching items that are only visited once.

Q: This architecture is from five years ago. Has it changed? Is it still scallable? What would the architecture look like today?

A:
**Has it changed?**
The problems (Timeline fan-out, GC pauses) are timeless. However, the custom "Twemproxy" solution has mostly been superseded by **Redis Cluster** (standardized in Redis 3.0) or service-mesh sidecars (Envoy) that handle sharding logic transparently. Twitter itself moved many persistent use cases to **Manhattan** (internal KV store) and **Pelikan** (unified cache).

**Is it scalable?**
**Yes.** Use of simple, sharded instances is the definition of horizontal scale.
*   **Limitation:** Managing thousands of independent Redis instances is operationally expensive ("N-squared" problem mentioned).

**What would the architecture look like today?**
1.  **Redis Cluster / managed services:** Today, we'd use **Redis Cluster** for automatic sharding and failover, or fully managed services like **Amazon ElastiCache** or **Redis Enterprise** which handle the "Cluster Management" layer that Twitter had to build themselves.
2.  **Tiered Storage:** Instead of "Hybrid Lists" for memory efficiency, modern Redis Enterprise offers **Redis on Flash** (SSD extension) or **DragonflyDB** (multi-threaded, high efficiency) to store TBs of data on a single instance without the fork hacks.
3.  **Rust Proxies:** If building a custom proxy today (Volta), engineers favor **Rust** (memory safety, no GC pauses) over C/C++ or Java. Twitter's "Pelikan" cache framework is an example of this modernization.

## Principal Architect's Q&A

**Q: Should I use Redis as a primary database?**

**A:** **No.** (With nuances).
1.  **Durability Risk**: Even with AOF (Append Only File), fsync settings often trade durability for speed. A power cycle can lose 1 second of data.
2.  **Memory Cost**: RAM is expensive. Storing TBs of data in RAM is bad economics. Use **SSDB** or **Redis on Flash** if you must.
3.  **Better Options**: If you need a fast KV store with persistence, use **ScyllaDB** (C++ Cassandra) or **FoundationDB**. Use Redis for ephemeral cache and rate limiting only.