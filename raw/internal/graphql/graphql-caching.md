Resource: https://youtu.be/qGSQauTcM-Q

Based on the transcript of the video **"GraphQL Caching Demystified"** by **Matteo Collina** at GraphQL Galaxy 2021, here is an accurate and comprehensive extraction of the content from start to end.

### **Introduction and Background**
Matteo Collina introduces himself as a member of the Node.js Technical Steering Committee and the Chief Software Architect at a company called NearForm. He shares his Twitter handle (@mateocolina) and mentions his newsletter, "Adventures in Nodeland."

He begins with a personal anecdote from the 90s about being fascinated by David Copperfield’s magic shows—specifically how things were made to fly or disappear. He draws a parallel to the presentation, stating that there is a lot of hard work behind magic. The goal of the talk is to apply "magic" to GraphQL to make latency disappear and improve the performance of a GraphQL gateway by four times.

### **Tools of the Craft**
Collina introduces the three main tools used for this demonstration:
1.  **Fastify:** Described as one of the fastest web frameworks for Node.js. It is modern, feature-rich, and similar to Express but faster.
2.  **Mercurius:** A GraphQL adapter that runs on top of Fastify. It supports features like Just-In-Time (JIT) compilation for queries and full federation (acting as either a gateway or a microservice).
3.  **Autocannon:** A load-testing tool written by Collina that allows users to script load tests in JavaScript.

### **The Experiment Setup**
The experiment involves a federated gateway connecting two services:
*   **User Service:** Offers a simple user object (ID and name).
*   **Post Service:** Offers post objects.
*   **Configuration:** The setup uses Mercurius with JIT compilation enabled. A cache module is integrated for resolvers, which can be toggled via arguments to run different experiments (e.g., no cache, zero-second TTL, 1-second TTL, etc.).
*   **Environment:** The services serve data directly from memory (no database involved), making them inherently fast. The benchmarks are run on dedicated hardware.

### **The Magic Trick: Benchmarking and Optimization**
Collina performs a live benchmark using Autocannon.

**1. Baseline (No Cache)**
*   He runs the benchmark against the gateway with caching disabled.
*   **Result:** Approximately **3,000 requests per second** with a p99 latency of **80 milliseconds**.
*   **Analysis:** A flame graph reveals that the vast majority of CPU time is spent performing HTTP requests (the gateway calling the services).

**2. Zero-Second TTL (The "Magic")**
*   He runs the benchmark again with the cache enabled but set to a **Time-To-Live (TTL) of zero seconds**.
*   **Result:** The performance jumps to **4x** the throughput (approx. 12,000 requests per second), and latency drops to **18 milliseconds**.
*   **Observation:** Even without storing the data for any length of time (0 seconds), performance improves drastically. Increasing the TTL further (to 1s or 10s) does not yield significant additional improvements in this specific setup because the target services are already fast and simple.

### **Explaining the Magic: Deduplication**
Collina explains how a zero-second cache provides such a massive boost.

**Flame Graph Analysis:**
In the optimized version, the block representing HTTP requests disappears from the flame graph. Instead, a large block appears representing the caching system. The bottleneck shifted from network I/O to the caching logic.

**The Mechanism (Deduplication):**
The improvement is due to **request deduplication**, not long-term caching.
*   **Event Loop Visualization:** Collina presents a diagram of the Node.js event loop from the perspective of function execution. When an event occurs, it calls into C++, then JavaScript. The JavaScript schedules promises or `nextTick` callbacks. Control returns to C++, which executes these tasks, and finally, control returns to the event loop. The time between the start and end of this cycle is when the loop is blocked.
*   **Promise Sharing:** When a resolver is executed, the system computes a cache key. It creates a promise for fetching the data. If a second request comes in for the exact same data *while the first promise is still pending* (within the same event loop tick), the system detects the matching cache key and returns the *existing* pending promise instead of firing a new request.
*   **Result:** Redundant computations and network requests are avoided entirely for concurrent requests.

**The Library:**
The module implementing this is called **`async-cache-dedupe`**. It allows defining asynchronous methods that automatically dedup and cache results.

### **Constructing the Cache Key**
To make this work, a robust cache key is required. Collina breaks down the anatomy of a GraphQL resolver in Node.js, which receives four arguments:
1.  **Root:** The current object.
2.  **Args:** Arguments for the resolver.
3.  **Context:** Request/response objects, DB connections, etc.
4.  **Info:** The query definition.

**Implementation Details:**
*   To generate a consistent key, one cannot simply `JSON.stringify` an object because property order varies.
*   Collina uses a library called **`safe-stable-stringify`**, which is deterministic regardless of property order.
*   The cache key is computed by navigating the `info` object to get the field selection and combining it with the root, arguments, and other relevant parameters.

### **Distributed Caching with Redis**
While in-process caching works well, it has limitations (data expiring on one node doesn't expire on others). The solution is a shared cache using **Redis**.

**The Problem:**
*   When implementing Redis, Collina encountered a new bottleneck.
*   With high traffic (e.g., thousands of requests/sec, each invoking 20 resolvers), the system generated massive amounts of Redis `GET` calls (e.g., 2,000 gets/sec).
*   **Latency:** While the internal Redis round-trip time is fast (0.5ms), the actual network round-trip time is around **15ms**. Sending requests sequentially caused "head-of-line blocking."

**The Solution (Automatic Pipelining):**
*   Collina references a technique he presented at RedisConf 2021 applied to the `ioredis` client.
*   **Batching:** The system groups multiple Redis commands generated within the same event loop iteration and sends them as a single **Redis Pipeline** batch.
*   **Result:** This cuts down the network round-trip overhead significantly.

### **Real-World Production Impact**
Collina shares data from a live production system using these techniques:
*   **Throughput:** 100x improvement in requests per second.
*   **Expansion Factor:** Each complex query generates about 15 Redis `GET` operations on average.
*   **Stability:** Redis handles the load without issues ("not even blinking an eye").

### **The Unsolved Problem: Invalidation**
Collina humorously notes that there are two hard things in computer science: naming things and **cache invalidation**.
*   He admits that he "ran out of time" to cover invalidation in the talk but then reveals that his team is actively working on it.
*   **Announcement:** Capability to invalidate cache both locally and on Redis will be added to `async-cache-dedupe` soon.

### **Conclusion**
Collina concludes by thanking the audience and inviting them to reach out to him on Twitter (@mateocolina) for questions. He encourages checking his newsletter and watching for upcoming announcements regarding the cache invalidation features.