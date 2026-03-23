Resource: https://youtu.be/eTad5SAk3vQ?list=TLGGhamu5Y49jaQxNTAyMjAyNg

Based on the video transcript "Edgestore Multi-tenancy & Isolation," here is an accurate and comprehensive extraction of the presentation by Bogdan Montano, a tech lead for the Core Team at Dropbox.

### **Introduction to Edgestore**
Edgestore is a strongly consistent metadata store built on top of thousands of MySQL shards. It powers nearly all Dropbox products and features. Originally, Dropbox had individual databases, but they eventually built Edgestore as a "database as a service" to provide a highly available, scalable, and durable solution. The goal was to abstract away sharding and caching operational burdens from product engineers.

**Architecture:**
*   **Clients:** Python and Go libraries run on application servers.
*   **The Core:** A stateless frontend service with hundreds of machines. It handles routing requests to the appropriate MySQL shard and manages a look-aside cache.
*   **Consistency:** It utilizes a two-phase commit-like protocol to ensure the cache and database remain in sync (strong consistency).
*   **The Engine:** A process running on the same machines as MySQL. This layer converts Protocol Buffers to SQL, handles connection pooling, and manages load control/multi-tenancy.
*   **MySQL Storage:** Owned by a sister DBA team. Edgestore uses a single deployment for all users (one service endpoint) rather than separate clusters for different tenants.
*   **Scale:** The system comprises 248 shards with a master/two-slave semi-sync setup and multi-region replication.

### **Data Layout and Workloads**
**Schema:**
Edgestore uses a single "main" table to store data for disparate entities (e.g., Teams, Users).
*   **Columns:** A "table/schema name," an ID tuple (logical shard ID + object ID), and a Data column (custom encoding similar to JSON).
*   **Sharding:** Data sharing the same logical shard ID is physically collocated, providing a foundational level of isolation (if one shard goes down, it doesn't impact 100% of traffic).

**API:**
The API is "close to NoSQL" but supports:
*   CRUD operations with Compare-and-Set semantics.
*   Batch requests (updating/reading thousands of objects).
*   Range scans, counts, and historical data fetching (log API).
*   Long-lived transactions where applications acquire read/write locks.

**Workloads:**
*   The system handles 10 million queries per second (QPS) total. Due to a 90% cache hit ratio, the Engine sees ~1.5 million QPS, translating to 2-3 million QPS on the MySQL fleet.
*   Traffic is highly varied: requests can return 1 row or 100,000 rows; batch sizes range from 1 to 1,000; payload sizes range from bytes to megabytes.

### **Isolation and Resource Management**
The "Engine" is responsible for controlling load to prevent MySQL from falling over. Isolation is managed through several layers:

**1. Request Size Isolation:**
To ensure fairness between small and large requests, the Engine uses a "Resource Pool" (token-based connection pool).
*   **Long-lived transactions:** A connection/token is reserved for the duration of the transaction.
*   **Large Reads:** The Engine parallelizes large requests (e.g., sending 50-100 parallel requests to MySQL) but limits parallelism to prevent resource exhaustion.
*   **Batch Requests:** Large batches are split into expensive "slices" that are executed sequentially.

**2. Traffic Type Isolation:**
Dropbox separates traffic into four distinct Resource Pools based on criticality and operation type:
*   **Write Live**
*   **Read Live**
*   **Write Offline** (Async/Scripts)
*   **Read Offline**
Resources are statically allocated and not moved between pools. If a pool is full, requests wait or time out.

**3. Tenant Identification:**
For finer granularity, Dropbox defines a "tenant" via tagging. Tags include the source machine, service name (e.g., File Sync), and schema/table. Intermediary services (like async workers) utilize plugins to pass tags tracking the *original* requester.

### **Resource Tracking Metrics**
Standard metrics (CPU, Memory, Network) were insufficient or not the bottleneck for the Engine. The critical resources were MySQL Disk I/O and CPU.
*   **The Proxy Metric:** Initially, they tracked **"Connection Seconds"** (number of connections $\times$ duration). This normalized usage across high-concurrency short requests and low-concurrency long requests.
*   **Correction:** They later realized "Connection Seconds" was flawed for long-lived transactions that had significant idle time. They switched to tracking **Execution Time** (time actually spent executing inside MySQL).

### **Throttling: Automated vs. Manual**
**Automated Throttling Mechanism:**
The team built a system to detect and mitigate "bad" tenants automatically:
*   **Trigger:** System detects errors or slowdowns.
*   **Identify:** It compares current usage to "The Good Old Times" (steady state) to find tenants with spiked resource usage.
*   **Action:** It automatically throttles that tenant to a calculated percentage (not zero) to restore system health.
*   **Outcome:** They **disabled** this system in production.

**The "Harsh Reality" & Manual Approach:**
They reverted to a manual approach because automation masked root causes. By forcing engineers to investigate alerts manually:
*   **Tooling:** They built a CLI tool that visualizes execution time per tenant and allows operators to issue throttling commands manually.
*   **Incident Response:** This reduced Mean Time to Repair (MTTR). The workflow became: Detect $\rightarrow$ Investigate (via tool) $\rightarrow$ Contain (Throttle) $\rightarrow$ Long-term Fix.
*   **Long-term Fixes:** Instead of just throttling, they focused on fixing the underlying issues, such as inefficient APIs (adding pagination), bad query optimization, or documentation gaps.

### **Lessons Learned & Future Work**
*   **One Deployment:** A single deployment works well for their scale and simplifies management.
*   **Avoid Premature Automation:** Automating throttling too soon reduced the incentive to fix root causes (e.g., bad code or schemas). "Taking the pain" of waking up at night led to better system stability in the long run.
*   **No Predefined Quotas:** Strict quotas don't work for their varied workloads. Tenants are allowed to use available resources in steady state.
*   **Future Plans:** They are building a "Control Plane Brain" to re-introduce automated throttling now that they understand the data better, aiming for lower granularity throttling (e.g., throttling specific hot rows rather than whole services).

### **Q&A Highlights**
*   **Usage:** Edgestore is the recommended storage for all internal Dropbox services, replacing legacy MySQL tables.
*   **JSON Support:** They built custom encoding because MySQL JSON support wasn't ready at the time, but they may revisit it.
*   **Incentives:** The speaker emphasized that engineers are more motivated to fix root problems when they get paged, which is why they preferred manual intervention over silent automated throttling.
*   **Open Source:** Much of Edgestore relies on internal Dropbox infrastructure, making it difficult to open source without significant resources.